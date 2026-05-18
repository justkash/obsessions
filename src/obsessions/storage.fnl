;; obsessions.nvim - storage module
;; MessagePack serialisation with atomic write-to-temp-then-rename.

(local M {})
(local uv vim.uv)

(fn M.encode [data]
  "Encode a Lua table to MessagePack bytes."
  (vim.mpack.encode data))

(fn M.decode [bytes]
  "Decode MessagePack bytes to a Lua table."
  (vim.mpack.decode bytes))

(fn M.write [path data]
  "Atomically write `data` (a Lua table) as MessagePack to `path`.
   Writes to a temporary file first, then renames into place.
   Returns true on success, (nil, err) on failure."
  (let [tmp (.. path ".tmp." (tostring (uv.getpid)) "." (tostring (uv.hrtime)))
        encoded (M.encode data)
        (fd err) (uv.fs_open tmp "w" 438)] ;; 0o666
    (if (not fd)
        (values nil (.. "failed to open tmp file: " (or err "unknown")))
        (do
          (let [(_ write-err) (uv.fs_write fd encoded)]
            (uv.fs_fsync fd)
            (uv.fs_close fd)
            (if write-err
                (do
                  (uv.fs_unlink tmp)
                  (values nil (.. "failed to write: " write-err)))
                (let [(_ rename-err) (uv.fs_rename tmp path)]
                  (if rename-err
                      (do
                        (uv.fs_unlink tmp)
                        (values nil (.. "failed to rename: " rename-err)))
                      true))))))))

(fn M.read [path]
  "Read a MessagePack file at `path` and return the decoded Lua table.
   Returns (nil, err) on failure."
  (let [(fd err) (uv.fs_open path "r" 438)]
    (if (not fd)
        (values nil (.. "failed to open: " (or err "unknown")))
        (let [(stat _) (uv.fs_fstat fd)]
          (if (not stat)
              (do (uv.fs_close fd)
                  (values nil "failed to stat file"))
              (let [(bytes _) (uv.fs_read fd stat.size)]
                (uv.fs_close fd)
                (if (not bytes)
                    (values nil "failed to read file")
                    (let [(ok result) (pcall M.decode bytes)]
                      (if ok
                          result
                          (values nil (.. "failed to decode: " (tostring result))))))))))))

(fn M.delete [path]
  "Delete the file at `path`. Returns true on success, (nil, err) on failure."
  (let [(_ err) (uv.fs_unlink path)]
    (if err
        (values nil (.. "failed to delete: " err))
        true)))

(fn M.exists [path]
  "Return true if `path` exists."
  (let [(stat _) (uv.fs_stat path)]
    (not= stat nil)))

M
