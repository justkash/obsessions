;; obsessions.nvim - pickers.select
;; Fallback picker using vim.ui.select (no external dependencies).

(local M {})

(fn M.pick [opts]
  "Display sessions using vim.ui.select.
   `opts` contains :sessions, :prompt, :action, :on-select."
  (let [sessions opts.sessions
        items (icollect [_ s (ipairs sessions)]
                (let [time (os.date "%Y-%m-%d %H:%M" s.mtime)]
                  (.. s.name " (" time ")")))
        name-map (collect [i s (ipairs sessions)]
                   (values (. items i) s.name))]
    (vim.ui.select items
      {:prompt (or opts.prompt "Select session")}
      (fn [choice]
        (when choice
          (let [name (. name-map choice)]
            (when (and name opts.on-select)
              ;; Let the command-line picker fully close before mutating
              ;; tabs/windows, otherwise the temporary command area height can
              ;; leak into the restored layout.
              (vim.schedule
                (fn []
                  (vim.cmd "redraw")
                  (opts.on-select name))))))))))

M
