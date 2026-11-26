{
  lib,
  callPackage,
  nixosTests,
  symlinkJoin,
  makeBinaryWrapper,
  flux-core,
  flux-sched,
  flux-security,
  flux-accounting,
  withSched ? true,
  withAccounting ? true,
}:

let
  inherit (flux-core) luaEnv luaVersion pythonVersion;
in
symlinkJoin {
  pname = "flux-framework";
  inherit (flux-core) version;

  paths = [
    flux-core
    flux-security
  ]
  ++ lib.optional withSched flux-sched
  ++ lib.optional withAccounting flux-accounting;

  nativeBuildInputs = [ makeBinaryWrapper ];

  # flux-core only searches its own prefix for modules, commands and rc
  # scripts. Point it at the joined tree so flux-sched and flux-accounting
  # are found too.
  postBuild = ''
    for prog in flux flux-python; do
      if [ -e "$out/bin/$prog" ]; then
        wrapProgram "$out/bin/$prog" \
          --set FLUX_LUA_PATH_PREPEND "$out/share/lua/${luaVersion}/?.lua" \
          --set FLUX_LUA_CPATH_PREPEND "$out/lib/lua/${luaVersion}/?.so" \
          --set FLUX_EXEC_PATH "$out/libexec/flux/cmd" \
          --set FLUX_PYTHONPATH_PREPEND "$out/lib/flux/python${pythonVersion}" \
          --set FLUX_CONNECTOR_PATH "$out/lib/flux/connectors" \
          --set FLUX_RC_EXTRA "$out/etc/flux" \
          --set FLUX_MODULE_PATH "$out/lib/flux/modules" \
          --set FLUX_MODPROBE_PATH_APPEND "$out/etc/flux/modprobe:$out/libexec/flux/modprobe"
      fi
    done

    # The job shell is started by the IMP or systemd with a sanitized
    # environment, so it cannot rely on the LUA_PATH set by `flux`. Give it
    # the flux Lua bindings (flux.shell defines the initrc helpers) and luaposix.
    wrapProgram "$out/libexec/flux/flux-shell" \
      --prefix LUA_PATH ';' "$out/share/lua/${luaVersion}/?.lua;${luaEnv}/share/lua/${luaVersion}/?.lua;${luaEnv}/share/lua/${luaVersion}/?/init.lua" \
      --prefix LUA_CPATH ';' "$out/lib/lua/${luaVersion}/?.so;${luaEnv}/lib/lua/${luaVersion}/?.so"

    # symlinkJoin's postBuild does not stop on a failed wrapper, so check.
    for f in bin/flux libexec/flux/flux-shell; do
      test -x "$out/$f" || { echo "missing wrapper: $f" >&2; exit 1; }
    done
  '';

  passthru = {
    inherit
      flux-core
      flux-sched
      flux-security
      flux-accounting
      ;
    tests = {
      smoke = callPackage ./smoke-test.nix { };
      nixos = nixosTests.flux-framework;
    };
  };

  meta = flux-core.meta // {
    description = "Flux resource manager with the Fluxion scheduler, security and accounting";
    mainProgram = "flux";
  };
}
