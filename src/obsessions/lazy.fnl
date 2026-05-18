;; obsessions.nvim - lazy module
;; Creates named buffer stubs that load their content on first access.
;; This enables fast session restore for large sessions.

(local M {})
(local api vim.api)

(var lazy-group nil)

(fn M.setup-lazy-autocmds [buf-map buffer-data]
  "Set up BufReadCmd autocmds for lazily-loaded buffer stubs.
   `buf-map` maps old bufnr strings to new bufnrs.
   `buffer-data` maps old bufnr strings to their captured info."
  ;; Create augroup (clear previous)
  (set lazy-group (api.nvim_create_augroup :ObsessionsLazy {:clear true}))

  (each [old-id new-bufnr (pairs buf-map)]
    (let [info (. buffer-data old-id)]
      (when (and info
                 (not info.is-terminal)
                 (> (length (or info.name "")) 0)
                 ;; Only for stubs that haven't been loaded
                 (api.nvim_buf_is_valid new-bufnr)
                 (= (api.nvim_buf_line_count new-bufnr) 1)
                 (= (. (api.nvim_buf_get_lines new-bufnr 0 1 false) 1) ""))
        ;; Attach a BufReadCmd autocmd for this buffer
        (api.nvim_create_autocmd [:BufReadCmd]
          {:group lazy-group
           :buffer new-bufnr
           :once true
           :callback
           (fn []
             ;; Actually load the file content
             (let [name (api.nvim_buf_get_name new-bufnr)]
               (when (and name (> (length name) 0)
                          (= (vim.fn.filereadable name) 1))
                 ;; Read file into buffer
                 (let [lines (vim.fn.readfile name)]
                   (api.nvim_set_option_value :modifiable true {:buf new-bufnr})
                   (api.nvim_buf_set_lines new-bufnr 0 -1 false lines)
                   (api.nvim_set_option_value :modified false {:buf new-bufnr})
                   ;; Trigger normal buffer events
                   (pcall vim.cmd (.. "doautocmd BufRead " (vim.fn.fnameescape name)))
                   ;; Restore filetype if known
                   (when info.filetype
                     (api.nvim_set_option_value "filetype" info.filetype {:buf new-bufnr})))))
             ;; Return false to allow other autocmds
             false)})))))

(fn M.cleanup []
  "Remove all lazy-load autocmds."
  (when lazy-group
    (api.nvim_del_augroup_by_id lazy-group)
    (set lazy-group nil)))

M
