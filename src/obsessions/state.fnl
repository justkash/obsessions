;; obsessions.nvim - state module
;; Captures and restores the full Neovim editor state:
;;   cwd, tabs, windows, buffers, terminals, marks, jumps, changes, location lists.

(local M {})
(local api vim.api)
(local fn* vim.fn)

(fn get-buf-option [bufnr option]
  (api.nvim_get_option_value option {:buf bufnr}))

(fn set-buf-option [bufnr option value]
  (api.nvim_set_option_value option value {:buf bufnr}))

;;; ===========================================================================
;;; Capture helpers
;;; ===========================================================================

(fn capture-buffer-info [bufnr]
  "Capture metadata for a single buffer."
  (let [name (api.nvim_buf_get_name bufnr)
        bt (get-buf-option bufnr "buftype")
        ft (get-buf-option bufnr "filetype")
        listed (get-buf-option bufnr "buflisted")]
    {:bufnr bufnr
     :name name
     :buftype bt
     :filetype ft
     :listed listed
     :is-terminal (= bt "terminal")}))

(fn capture-marks [bufnr]
  "Capture local marks (a-z) for a buffer."
  (let [marks {}]
    (for [i (string.byte "a") (string.byte "z")]
      (let [mark (string.char i)
            pos (api.nvim_buf_get_mark bufnr mark)]
        (when (and (> (. pos 1) 0))
          (tset marks mark pos))))
    marks))

(fn capture-global-marks []
  "Capture global marks (A-Z)."
  (let [marks {}]
    (for [i (string.byte "A") (string.byte "Z")]
      (let [mark (string.char i)
            pos (fn*.getpos (.. "'" mark))]
        (when (and pos (> (. pos 2) 0))
          (tset marks mark {:bufnr (. pos 1)
                            :lnum (. pos 2)
                            :col (. pos 3)}))))
    marks))

(fn capture-jumplist []
  "Capture the jump list for the current window."
  (let [(jumps current) (unpack (fn*.getjumplist))]
    {:entries (icollect [_ j (ipairs jumps)]
               {:bufnr j.bufnr
                :lnum j.lnum
                :col j.col
                :filename (let [name (api.nvim_buf_get_name j.bufnr)]
                            (when (and name (> (length name) 0)) name))})
     :current current}))

(fn capture-changelist [bufnr]
  "Capture the change list for a buffer."
  (let [(ok result) (pcall fn*.getchangelist bufnr)]
    (if ok
        (let [(changes current) (unpack result)]
          {:entries (icollect [_ c (ipairs changes)]
                     {:lnum c.lnum :col c.col})
           :current current})
        nil)))

(fn capture-loclist [winid]
  "Capture the location list for a window."
  (let [items (fn*.getloclist winid)]
    (when (and items (> (length items) 0))
      (icollect [_ item (ipairs items)]
        {:bufnr item.bufnr
         :lnum item.lnum
         :col item.col
         :text item.text
         :type item.type
         :filename (when (> item.bufnr 0)
                     (api.nvim_buf_get_name item.bufnr))}))))

(fn capture-window [winid]
  "Capture state for a single window."
  (let [bufnr (api.nvim_win_get_buf winid)
        cursor (api.nvim_win_get_cursor winid)
        (width height) (values (api.nvim_win_get_width winid)
                                (api.nvim_win_get_height winid))
        buf-info (capture-buffer-info bufnr)]
    {:winid winid
     :buffer buf-info
     :cursor cursor
     :width width
     :height height
     :loclist (capture-loclist winid)}))

(fn capture-layout-tree [layout]
  "Recursively capture the window layout tree from vim.fn.winlayout().
   Returns a nested structure describing splits and leaf windows."
  (let [kind (. layout 1)]
    (if (= kind "leaf")
        {:type :leaf
         :winid (. layout 2)}
        ;; row or col
        {:type kind
         :children (icollect [_ child (ipairs (. layout 2))]
                     (capture-layout-tree child))})))

(fn capture-tab [tabnr]
  "Capture the full state of a single tab page."
  (let [tabpage (. (api.nvim_list_tabpages) tabnr)
        wins (api.nvim_tabpage_list_wins tabpage)
        layout (fn*.winlayout tabnr)
        (size-ok size-cmd) (if (> (length wins) 0)
                               (pcall api.nvim_win_call (. wins 1) fn*.winrestcmd)
                               (values false nil))
        win-states {}]
    ;; Capture each window's state
    (each [_ winid (ipairs wins)]
      (tset win-states (tostring winid) (capture-window winid)))
    {:tabnr tabnr
     :tabpage tabpage
     :layout (capture-layout-tree layout)
     :size-cmd (if size-ok size-cmd nil)
     :windows win-states
     :active-window (api.nvim_tabpage_get_win tabpage)}))

;;; ===========================================================================
;;; Top-level capture
;;; ===========================================================================

(fn M.capture []
  "Capture the entire editor state. Returns a serialisable table."
  (let [tabs (api.nvim_list_tabpages)
        current-tab (api.nvim_get_current_tabpage)
        ;; Collect all listed buffers (including unlisted terminals)
        all-bufs (icollect [_ b (ipairs (api.nvim_list_bufs))]
                   (when (or (get-buf-option b "buflisted")
                             (= (get-buf-option b "buftype") "terminal"))
                     b))
        buf-data {}
        buf-marks {}
        buf-changes {}]
    ;; Per-buffer data
    (each [_ bufnr (ipairs all-bufs)]
      (let [info (capture-buffer-info bufnr)]
        (tset buf-data (tostring bufnr)
              (vim.tbl_extend :force info
                              {:marks (capture-marks bufnr)
                               :changelist (capture-changelist bufnr)}))))
    ;; Per-tab data
    (let [tab-data (icollect [idx _ (ipairs tabs)]
                     (capture-tab idx))]
      {:version 1
       :cwd (fn*.getcwd)
       :buffers buf-data
       :buffer-order (icollect [_ b (ipairs all-bufs)] b)
       :tabs tab-data
       :active-tab (let [ct (api.nvim_get_current_tabpage)]
                     ;; find 1-based index
                     (var idx 1)
                     (each [i tp (ipairs tabs)]
                       (when (= tp ct) (set idx i)))
                     idx)
       :global-marks (capture-global-marks)
       :jumplist (capture-jumplist)
       :timestamp (os.time)})))

;;; ===========================================================================
;;; Restore helpers
;;; ===========================================================================

(fn close-all-buffers []
  "Close all current buffers and tabs to prepare for restore."
  ;; Close all windows/tabs except one
  (vim.cmd "silent! tabonly!")
  (vim.cmd "silent! only!")
  ;; Delete all buffers
  (each [_ bufnr (ipairs (api.nvim_list_bufs))]
    (when (api.nvim_buf_is_valid bufnr)
      (pcall api.nvim_buf_delete bufnr {:force true}))))

(fn create-buffer-stub [buf-info lazy?]
  "Create a buffer for the given info. If `lazy?`, create a named stub.
   Returns the new buffer number."
  (if buf-info.is-terminal
      ;; Terminal: open a new terminal (no command replay)
      (let [bufnr (api.nvim_create_buf true false)]
        bufnr)
      ;; Regular file
      (if (and lazy? (> (length (or buf-info.name "")) 0))
          ;; Lazy stub: create unlisted buf, set name, make listed
          (let [bufnr (api.nvim_create_buf true false)]
            (when (> (length buf-info.name) 0)
              (pcall api.nvim_buf_set_name bufnr buf-info.name))
            (set-buf-option bufnr "buflisted" buf-info.listed)
            bufnr)
          ;; Eager: actually edit the file
          (let [bufnr (api.nvim_create_buf true false)]
            (when (> (length (or buf-info.name "")) 0)
              (pcall api.nvim_buf_set_name bufnr buf-info.name)
              ;; Read file content
              (pcall vim.cmd (.. "silent! buffer " bufnr))
              (pcall vim.cmd "silent! edit"))
            bufnr))))

(fn restore-marks [bufnr marks]
  "Restore local marks for a buffer."
  (when marks
    (each [mark pos (pairs marks)]
      (pcall api.nvim_buf_set_mark bufnr mark (. pos 1) (. pos 2) {}))))

(fn collect-layout-leaves [node acc]
  "Collect saved leaf window IDs in layout order."
  (let [leaves (or acc [])]
    (if (not node)
        leaves
        (if (= node.type :leaf)
            (do
              (when node.winid
                (table.insert leaves (tostring node.winid)))
              leaves)
            (do
              (each [_ child (ipairs (or node.children []))]
                (collect-layout-leaves child leaves))
              leaves)))))

(fn restore-window-state [new-winid win-state buf-map]
  "Apply a saved window state to a restored window."
  (when (and new-winid (api.nvim_win_is_valid new-winid) win-state)
    (let [buf-info win-state.buffer]
      (when buf-info
        (let [old-bufnr (tostring buf-info.bufnr)]
          (if buf-info.is-terminal
              (do
                (M.open-terminal-in-window new-winid)
                (tset buf-map old-bufnr (api.nvim_win_get_buf new-winid)))
              (let [new-bufnr (. buf-map old-bufnr)]
                (when new-bufnr
                  (pcall api.nvim_win_set_buf new-winid new-bufnr)))))
        (when (and (not buf-info.is-terminal) win-state.cursor)
          (pcall api.nvim_win_set_cursor new-winid win-state.cursor))))))

(fn restore-window-dimensions [new-winid win-state]
  "Fallback when no tab-level size command is available."
  (when (and new-winid (api.nvim_win_is_valid new-winid) win-state)
    (pcall api.nvim_win_set_width new-winid (or win-state.width 80))
    (pcall api.nvim_win_set_height new-winid (or win-state.height 24))))

(fn restore-tab-sizes [tab old-winids wins win-map]
  "Restore split sizing for a tab.
   Prefer the captured winrestcmd(), falling back to per-window sizes."
  (if (and tab.size-cmd (> (length wins) 0))
      (let [anchor-win (. wins 1)]
        (when (and anchor-win (api.nvim_win_is_valid anchor-win))
          (pcall api.nvim_win_call anchor-win
                 (fn []
                   (vim.cmd tab.size-cmd)))))
      (each [_ old-winid (ipairs old-winids)]
        (let [new-winid (. win-map old-winid)
              win-state (. tab.windows old-winid)]
          (restore-window-dimensions new-winid win-state)))))

(fn restore-layout-tree [node]
  "Recursively restore a window layout tree.
   Returns the list of window IDs created."
  (if (= node.type :leaf)
      ;; Leaf: the current window is already our target
      (let [winid (api.nvim_get_current_win)]
        [winid])
      ;; Split
      (let [children (or node.children [])
            child-roots [(api.nvim_get_current_win)]
            all-wins []]
        ;; Create sibling regions first so nested children don't steal
        ;; their parent's split when they recurse.
        (each [idx _ (ipairs children)]
          (when (> idx 1)
            (let [prev-root (. child-roots (- idx 1))]
              (when (and prev-root (api.nvim_win_is_valid prev-root))
                (api.nvim_set_current_win prev-root))
              (if (= node.type "row")
                  (vim.cmd "belowright vsplit")
                  (vim.cmd "belowright split"))
              (table.insert child-roots (api.nvim_get_current_win)))))
        (each [idx child (ipairs children)]
          (let [child-root (. child-roots idx)]
            (when (and child-root (api.nvim_win_is_valid child-root))
              (api.nvim_set_current_win child-root)
              (let [wins (restore-layout-tree child)]
                (each [_ w (ipairs wins)]
                  (table.insert all-wins w))))))
        all-wins)))

;;; ===========================================================================
;;; Top-level restore
;;; ===========================================================================

(fn M.restore [state lazy?]
  "Restore editor state from a captured state table.
   `lazy?` controls whether non-visible buffers are loaded lazily."
  (if (not state)
      (values nil "no state to restore")
      (do
        ;; 1. Set cwd
        (when state.cwd
          (vim.cmd (.. "cd " (fn*.fnameescape state.cwd))))

        ;; 2. Close everything
        (close-all-buffers)

        ;; 3. Create buffers (map old bufnr → new bufnr)
        (let [buf-map {}
              visible-bufs {}]
          ;; First pass: determine which buffers are visible
          (when state.tabs
            (each [_ tab (ipairs state.tabs)]
              (each [_ win-state (pairs tab.windows)]
                (when win-state.buffer
                  (tset visible-bufs (tostring win-state.buffer.bufnr) true)))))

          ;; Second pass: create all buffers
          (each [old-id buf-info (pairs (or state.buffers {}))]
            (let [is-visible (. visible-bufs old-id)
                  use-lazy (and lazy? (not is-visible) (not buf-info.is-terminal))
                  new-bufnr (create-buffer-stub buf-info use-lazy)]
              (tset buf-map old-id new-bufnr)
              ;; Restore marks
              (when buf-info.marks
                (restore-marks new-bufnr buf-info.marks))))

          ;; 4. Restore tabs and window layouts
          (when (and state.tabs (> (length state.tabs) 0))
            ;; First tab uses existing tab
            (each [tidx tab (ipairs state.tabs)]
              (when (> tidx 1)
                (vim.cmd "tabnew"))

              ;; Restore window layout
              (when tab.layout
                (let [wins (restore-layout-tree tab.layout)
                      old-winids (collect-layout-leaves tab.layout)
                      win-map {}]
                  (each [idx old-winid (ipairs old-winids)]
                    (let [new-winid (. wins idx)
                          win-state (. tab.windows old-winid)]
                      (when (and new-winid win-state)
                        (tset win-map old-winid new-winid)
                        (restore-window-state new-winid win-state buf-map))))
                  (restore-tab-sizes tab old-winids wins win-map)
                  (when tab.active-window
                    (let [active-winid (. win-map (tostring tab.active-window))]
                      (when (and active-winid (api.nvim_win_is_valid active-winid))
                        (pcall api.nvim_set_current_win active-winid))))))))

          ;; 5. Go to active tab
          (when state.active-tab
            (pcall vim.cmd (.. "tabnext " state.active-tab)))

          ;; 6. Setup lazy-load autocmds
          (when lazy?
            (let [lazy-mod (require :obsessions.lazy)]
              (lazy-mod.setup-lazy-autocmds buf-map state.buffers)))

          ;; Return the buffer map for reference
          buf-map))))

;;; ===========================================================================
;;; Terminal restoration
;;; ===========================================================================

(fn M.open-terminal-in-window [winid]
  "Open a terminal buffer in the specified window (no command replay)."
  (when (api.nvim_win_is_valid winid)
    (api.nvim_set_current_win winid)
    (vim.cmd "terminal")))

(fn M.open-new-session-terminal [layout-type height width]
  "Open the initial terminal for a new session.
   `height` is used for the :bottom layout; `width` is used for :right."
  (match layout-type
    :fullscreen (vim.cmd "terminal")
    :bottom (do (vim.cmd "botright split | terminal")
                (vim.cmd (.. "resize " (tostring (or height 15)))))
    :right (do (vim.cmd "vertical botright split | terminal")
               (vim.cmd (.. "vertical resize " (tostring (or width 80)))))
    _ (vim.cmd "terminal")))

M
