;; obsessions.nvim - pickers.fzf_lua
;; fzf-lua adapter for session picking.

(local M {})

(fn vim-to-fzf-key [key]
  "Translate a vim-style key (e.g. <C-d>) to the fzf-lua action key
   (e.g. ctrl-d). Keys that are already in fzf style pass through."
  (let [lower (key:lower)
        (k1 _) (lower:gsub "<c%-(%w+)>" "ctrl-%1")
        (k2 _) (k1:gsub "<m%-(%w+)>" "alt-%1")
        (k3 _) (k2:gsub "<a%-(%w+)>" "alt-%1")
        (k4 _) (k3:gsub "<s%-(%w+)>" "shift-%1")]
    k4))

(fn make-previewer [builtin record-map]
  "Build an fzf-lua builtin previewer class that renders the buffers of the
   session under the cursor into the preview (secondary) window. `record-map`
   maps each display line back to its {:name :path :mtime} session record."
  (let [Previewer (builtin.buffer_or_file:extend)]
    (fn Previewer.new [self o opts fzf-win]
      (Previewer.super.new self o opts fzf-win)
      (setmetatable self Previewer)
      self)
    (fn Previewer.populate_preview_buf [self entry-str]
      (let [tmpbuf (self:get_tmp_buffer)
            preview (require :obsessions.pickers.preview)
            record (. record-map entry-str)
            lines (if record
                      (preview.build-lines record)
                      ["(no session selected)"])]
        (vim.api.nvim_buf_set_lines tmpbuf 0 -1 false lines)
        (self:set_preview_buf tmpbuf)
        (pcall (fn [] (self.win:update_preview_title " Session Buffers ")))
        (pcall (fn [] (self.win:update_preview_scrollbar)))))
    (fn Previewer.gen_winopts [self]
      (vim.tbl_extend :force self.winopts {:wrap false :number false}))
    Previewer))

(fn M.pick [opts]
  "Display sessions using fzf-lua.
   `opts` contains :sessions, :prompt, :action, :keymaps, :on-select,
   :on-delete, :on-rename."
  (let [(ok fzf) (pcall require :fzf-lua)
        (ok-builtin builtin) (pcall require :fzf-lua.previewer.builtin)]
    (if (not ok)
        (do
          (vim.notify "Obsessions: fzf-lua not available" vim.log.levels.ERROR)
          nil)
        (let [sessions opts.sessions
              keymaps (or opts.keymaps {})
              delete-key (vim-to-fzf-key (or keymaps.delete "<C-d>"))
              rename-key (vim-to-fzf-key (or keymaps.rename "<C-r>"))
              create-key (vim-to-fzf-key (or keymaps.create "<C-n>"))
              items []
              name-map {}
              ;; display line -> {:name :path :mtime} record, used by the
              ;; previewer to read the session's buffers on demand.
              record-map {}
              actions {:default (fn [selected]
                                  (when (and selected (> (length selected) 0))
                                    (let [choice (. selected 1)
                                          name (. name-map choice)]
                                      (when (and name opts.on-select)
                                        (opts.on-select name)))))}]
          (each [_ s (ipairs sessions)]
            (let [display (string.format "%-30s %s"
                            s.name
                            (os.date "%Y-%m-%d %H:%M" s.mtime))]
              (table.insert items display)
              (tset name-map display s.name)
              (tset record-map display s)))
          (when opts.on-delete
            (tset actions delete-key
                  (fn [selected]
                    (when (and selected (> (length selected) 0))
                      (let [choice (. selected 1)
                            name (. name-map choice)]
                        (when name
                          (opts.on-delete name)))))))
          (when opts.on-rename
            (tset actions rename-key
                  (fn [selected]
                    (when (and selected (> (length selected) 0))
                      (let [choice (. selected 1)
                            name (. name-map choice)]
                        (when name
                          (opts.on-rename name)))))))
          (when opts.on-create
            ;; Create needs no selection; ignore the selected entry.
            (tset actions create-key
                  (fn [_]
                    (opts.on-create))))
          (fzf.fzf_exec items
            {:prompt (.. (or opts.prompt "Sessions") "> ")
             :previewer (when ok-builtin (make-previewer builtin record-map))
             :actions actions})))))

M
