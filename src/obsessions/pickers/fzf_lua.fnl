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

(fn M.pick [opts]
  "Display sessions using fzf-lua.
   `opts` contains :sessions, :prompt, :action, :keymaps, :on-select,
   :on-delete, :on-rename."
  (let [(ok fzf) (pcall require :fzf-lua)]
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
              (tset name-map display s.name)))
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
             :actions actions})))))

M
