{ lib
, luajitPackages
, pname
, stdenvNoCC
, version
, vimUtils
}:
vimUtils.toVimPlugin (stdenvNoCC.mkDerivation {
  inherit pname;
  inherit version;

  __structuredAttrs = true;

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      (lib.fileset.fileFilter (file: file.hasExt "fnl") ../src)
      ../plugin/obsessions.lua
    ];
  };

  nativeBuildInputs = [ luajitPackages.fennel ];

  dontUnpack = true;

  buildPhase = ''
    compile_fnl_in_dir() {
      local src_dir="$1"
      local dest_dir="$2"
      
      mkdir -p "$dest_dir"
      
      for file in "$src_dir"/*.fnl; do
        if [ -f "$file" ]; then
          filename=$(basename "$file" .fnl)
          echo "Compiling $file -> $dest_dir/$filename.lua"
          fennel --compile "$file" > "$dest_dir/$filename.lua"
        fi
      done
      
      # Recurse into subdirectories
      for dir in "$src_dir"/*/; do
        if [ -d "$dir" ]; then
          dirname=$(basename "$dir")
          compile_fnl_in_dir "$dir" "$dest_dir/$dirname"
        fi
      done
    }

    export HOME=$TMPDIR
    export XDG_CACHE_HOME=$TMPDIR/.cache
    mkdir -p $XDG_CACHE_HOME
    
    build_dir="$TMPDIR/build"
    mkdir -p "$build_dir/lua" "$build_dir/plugin"
    compile_fnl_in_dir "$src/src" "$build_dir/lua"
    cp "$src/plugin/${pname}.lua" "$build_dir/plugin/${pname}.lua"
  '';
  
  installPhase = ''
    build_dir="$TMPDIR/build"
    mkdir -p "$out"
    cp -r "$build_dir"/. "$out"/
  '';

  nvimRequireCheck = [
    "obsessions"
    "obsessions.autosave"
    "obsessions.config"
    "obsessions.lazy"
    "obsessions.lock"
    "obsessions.picker"
    "obsessions.pickers.fzf_lua"
    "obsessions.pickers.select"
    "obsessions.pickers.telescope"
    "obsessions.session"
    "obsessions.state"
    "obsessions.storage"
  ];
})
