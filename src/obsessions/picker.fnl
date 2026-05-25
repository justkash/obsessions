;; obsessions.nvim - picker module
;; Abstract picker interface. Delegates to telescope, fzf-lua, or vim.ui.select.

(local M {})
(local config (require :obsessions.config))

(fn detect-picker []
  "Auto-detect available picker backend. Returns a string key."
  (let [cfg (config.get)
        pref cfg.picker]
    (if (and (not= pref :auto) (not= pref nil))
        pref
        ;; Auto-detect
        (if (pcall require :telescope)
            :telescope
            (pcall require :fzf-lua)
            :fzf_lua
            ;; Fallback
            :select))))

(fn load-picker [backend]
  "Load and return the picker adapter module for `backend`."
  (let [mod-name (.. "obsessions.pickers." backend)
        (ok mod) (pcall require mod-name)]
    (if ok
        mod
        (do
          (vim.notify (.. "Obsessions: picker '" backend "' not found, using select fallback")
                      vim.log.levels.WARN)
          (require :obsessions.pickers.select)))))

(fn delete-handler [name]
  "Default picker callback for the delete keymap."
  (let [session (require :obsessions.session)]
    (session.delete name)))

(fn rename-handler [name]
  "Default picker callback for the rename keymap. Prompts for a new name."
  (let [session (require :obsessions.session)]
    (vim.ui.input
      {:prompt (.. "Rename '" name "' to: ")
       :default name}
      (fn [new-name]
        (when (and new-name (not= new-name "") (not= new-name name))
          (let [(ok err) (session.rename name new-name)]
            (when (and (not ok) err)
              (vim.notify (.. "Obsessions: " err) vim.log.levels.ERROR))))))))

(fn create-handler []
  "Default picker callback for the create keymap. Prompts for a name and
   creates a brand new session. Takes no selection."
  (let [session (require :obsessions.session)]
    (vim.ui.input
      {:prompt "New session name: "}
      (fn [name]
        (when (and name (not= name ""))
          (let [(ok err) (session.create name)]
            (when (and (not ok) err)
              (vim.notify (.. "Obsessions: " err) vim.log.levels.ERROR))))))))

(fn M.pick-session [opts]
  "Open a session picker. `opts` is a table with:
     :action  - 'switch' | 'load' | 'delete' | 'rename' (default 'switch')
     :on-select - optional callback(session-name)
   If no on-select is given, performs the default action."
  (let [session (require :obsessions.session)
        cfg (config.get)
        sessions (session.list)
        backend (detect-picker)
        picker (load-picker backend)
        action (or (?. opts :action) :switch)
        keymaps (or cfg.picker-keymaps {})]
    (if (= (length sessions) 0)
        (vim.notify "Obsessions: no saved sessions" vim.log.levels.INFO)
        (picker.pick
          {:sessions sessions
           :prompt (.. "Sessions (" action ")")
           :action action
           :keymaps keymaps
           :on-select (or (?. opts :on-select)
                         (fn [name]
                           (match action
                             :switch (session.switch name)
                             :load (session.load name)
                             :delete (delete-handler name)
                             :rename (rename-handler name))))
           :on-delete delete-handler
           :on-rename rename-handler
           :on-create create-handler}))))

M
