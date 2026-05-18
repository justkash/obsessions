;; obsessions.nvim - config module
;; Default configuration, validation, and merging.

(local M {})

(local defaults
  {:storage-path (.. (vim.fn.stdpath :data) "/obsessions")
   :autosave-interval 300          ;; seconds; 0 to disable
   :restore-last-session false     ;; restore last session on VimEnter
   :picker :auto                   ;; "telescope" | "fzf_lua" | "select" | "auto"
   :lazy-load-buffers true         ;; create named stubs, load on access
   :new-session-layout :fullscreen ;; terminal layout for new sessions: "fullscreen" | "bottom" | "right"
   :new-session-terminal-height 15 ;; height when layout is "bottom"
   :new-session-terminal-width 80  ;; width when layout is "right"
   :lock-timeout 5000              ;; ms to wait for lock before giving up
   :picker-keymaps {:delete "<C-d>" ;; keys used inside the picker window
                    :rename "<C-r>"}})

(var config (vim.deepcopy defaults))

(fn normalise-keys [t]
  "Recursively replace `_` with `-` in string keys, so Lua users can pass
   `autosave_interval` and have it land on `autosave-interval`."
  (if (or (not= (type t) :table) (vim.islist t))
      t
      (let [out {}]
        (each [k v (pairs t)]
          (let [k* (if (= (type k) :string) (k:gsub "_" "-") k)]
            (tset out k* (normalise-keys v))))
        out)))

(fn M.setup [opts]
  "Merge user options into the config table. Keys use kebab-case in Fennel
   but users may pass snake_case from Lua; we normalise both."
  (let [normalised (normalise-keys (or opts {}))
        merged (vim.tbl_deep_extend :force (vim.deepcopy defaults) normalised)]
    ;; ensure storage directory exists
    (vim.fn.mkdir merged.storage-path :p)
    (set config merged))
  config)

(fn M.get []
  "Return the current config table (read-only reference)."
  config)

(fn M.get-value [key]
  "Return a single config value by key."
  (. config key))

M
