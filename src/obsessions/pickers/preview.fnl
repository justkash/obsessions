;; obsessions.nvim - pickers.preview
;; Shared helper that renders the buffers belonging to a saved session as a
;; list of display lines, for use in a picker's secondary/preview window.

(local M {})

(fn shorten [name]
  "Make a file path readable: relative to cwd or ~, falling back to the raw
   name. Unnamed buffers render as [No Name]."
  (if (or (not name) (= name ""))
      "[No Name]"
      (let [rel (vim.fn.fnamemodify name ":~:.")]
        (if (and rel (not= rel "")) rel name))))

(fn terminal-label [name]
  "Derive a short label for a terminal buffer from its term:// name.
   `term://<dir>//<pid>:<command>` -> `<command>`."
  (if (or (not name) (= name ""))
      "terminal"
      (or (name:match ".*//%d+:(.*)$") name)))

(fn collect-buffers [data]
  "Split a session's buffer records into ordered file and terminal lists.
   Honours `buffer-order` when present, otherwise iterates the buffer map."
  (let [buffers (or data.buffers {})
        order (or data.buffer-order [])
        files []
        terms []
        keys []]
    (if (> (length order) 0)
        (each [_ bufnr (ipairs order)]
          (table.insert keys (tostring bufnr)))
        (each [k _ (pairs buffers)]
          (table.insert keys k)))
    (each [_ key (ipairs keys)]
      (let [info (. buffers key)]
        (when info
          (if info.is-terminal
              (table.insert terms info)
              (table.insert files info)))))
    (values files terms)))

(fn M.build-lines [session]
  "Return a list of display lines describing the buffers in `session`
   (a {:name :path :mtime} record). Reads the session file on demand."
  (let [storage (require :obsessions.storage)
        (data err) (storage.read session.path)]
    (if (not data)
        [(.. "Could not read session: " (or err "unknown"))]
        (let [(files terms) (collect-buffers data)
              lines [session.name ""]]
          (if (and (= (length files) 0) (= (length terms) 0))
              (table.insert lines "(no buffers)")
              (do
                (when (> (length files) 0)
                  (table.insert lines (.. "Buffers (" (length files) ")"))
                  (each [_ info (ipairs files)]
                    (table.insert lines (.. "  " (shorten info.name))))
                  (table.insert lines ""))
                (when (> (length terms) 0)
                  (table.insert lines (.. "Terminals (" (length terms) ")"))
                  (each [_ info (ipairs terms)]
                    (table.insert lines (.. "  $ " (terminal-label info.name)))))))
          lines))))

M
