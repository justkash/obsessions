;; obsessions.nvim - pickers.telescope
;; Telescope.nvim adapter for session picking.

(local M {})

(fn M.pick [opts]
  "Display sessions using Telescope.
   `opts` contains :sessions, :prompt, :action, :keymaps, :on-select,
   :on-delete, :on-rename."
  (let [(ok-pickers pickers) (pcall require :telescope.pickers)
        (ok-finders finders) (pcall require :telescope.finders)
        (ok-conf conf) (pcall require :telescope.config)
        (ok-actions actions) (pcall require :telescope.actions)
        (ok-state action-state) (pcall require :telescope.actions.state)
        (ok-prev previewers) (pcall require :telescope.previewers)
        preview (require :obsessions.pickers.preview)]
    (if (not (and ok-pickers ok-finders ok-conf ok-actions ok-state))
        (do
          (vim.notify "Obsessions: telescope not available" vim.log.levels.ERROR)
          nil)
        (let [sessions opts.sessions
              keymaps (or opts.keymaps {})
              delete-key (or keymaps.delete "<C-d>")
              rename-key (or keymaps.rename "<C-r>")
              create-key (or keymaps.create "<C-n>")
              ;; Secondary window: list the buffers saved in the session under
              ;; the cursor. Optional - only when the previewer module loaded.
              session-previewer
              (when ok-prev
                (previewers.new_buffer_previewer
                  {:title "Session Buffers"
                   :define_preview
                   (fn [self entry _status]
                     (let [lines (preview.build-lines
                                   {:name entry.value :path entry.path})]
                       (vim.api.nvim_buf_set_lines self.state.bufnr 0 -1 false lines)))}))
              picker (pickers.new
                       {}
                       {:prompt_title (or opts.prompt "Sessions")
                        :finder (finders.new_table
                                  {:results sessions
                                   :entry_maker
                                   (fn [entry]
                                     {:value entry.name
                                      :path entry.path
                                      :display (string.format "%-30s %s"
                                                 entry.name
                                                 (os.date "%Y-%m-%d %H:%M" entry.mtime))
                                      :ordinal entry.name})})
                        :previewer session-previewer
                        :sorter (conf.values.generic_sorter {})
                        :attach_mappings
                        (fn [prompt-bufnr map]
                          (actions.select_default:replace
                            (fn []
                              (actions.close prompt-bufnr)
                              (let [selection (action-state.get_selected_entry)]
                                (when (and selection opts.on-select)
                                  (opts.on-select selection.value)))))
                          (when opts.on-delete
                            (let [del-fn (fn []
                                           (let [selection (action-state.get_selected_entry)]
                                             (when selection
                                               (actions.close prompt-bufnr)
                                               (opts.on-delete selection.value))))]
                              (map :i delete-key del-fn)
                              (map :n delete-key del-fn)))
                          (when opts.on-rename
                            (let [ren-fn (fn []
                                           (let [selection (action-state.get_selected_entry)]
                                             (when selection
                                               (actions.close prompt-bufnr)
                                               (opts.on-rename selection.value))))]
                              (map :i rename-key ren-fn)
                              (map :n rename-key ren-fn)))
                          (when opts.on-create
                            (let [create-fn (fn []
                                              ;; Create needs no selection; just
                                              ;; close the picker and prompt.
                                              (actions.close prompt-bufnr)
                                              (opts.on-create))]
                              (map :i create-key create-fn)
                              (map :n create-key create-fn)))
                          true)})]
          (picker:find)))))

M
