# ---
# --- FLAKE
# --- NITRO-FLAKE
# ---
{
  description = "Home Manager module: Nitro Service Manager";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }:
    {
      nixosModules = {
        default =
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            cfg = config.services.nitroctl;

            servicesDir = pkgs.runCommand "nitro-services" { } (
              let
                svcList = lib.attrsToList cfg.services;
                mkService = svc:
                  let
                    s = svc.value;
                    # Determine if template and get children
                    isRegularService = s.template == false || !(s.template ? true);
                    children = if lib.isList s.template
                               then s.template
                               else if s.template == true
                                    then []
                                    else [];

                    name = if isRegularService
                           then svc.name
                           else if (!isRegularService && lib.hasSuffix "@") svc.name
                                then svc.name
                                else "${svc.name}@";

                  in
                  ''
                    # Service Directories
                    mkdir -p "$out/${name}"
                    ${lib.concatMapStrings (child: ''
                      ln -s "$out/${name}" "$out/${name}${child}"
                    '') children}

                    # Service scripts
                    ## running -> presence/absence of 'down'
                    ${lib.optionalString (!s.running) ''
                      touch "$out/${name}/down"
                    ''}

                    ## setup
                    ${lib.optionalString (s.setup != "") ''
                      cat > "$out/${name}/setup" << 'EOF'
                    ${s.setup}
                    EOF
                      chmod +x "$out/${name}/setup"
                    ''}

                    ## run
                    ${lib.optionalString (s.run != "") ''
                      cat > "$out/${name}/run" << 'EOF'
                    ${s.run}
                    EOF
                      chmod +x "$out/${name}/run"
                    ''}

                    ## finish
                    ${lib.optionalString (s.finish != "") ''
                      cat > "$out/${name}/finish" << 'EOF'
                    ${s.finish}
                    EOF
                      chmod +x "$out/${name}/finish"
                    ''}

                    ## final
                    ${lib.optionalString (s.finish != "") ''
                      cat > "$out/${name}/final" << 'EOF'
                    ${s.final}
                    EOF
                      chmod +x "$out/${name}/final"
                    ''}

                    ## fatal
                    ${lib.optionalString (s.finish != "") ''
                      cat > "$out/${name}/fatal" << 'EOF'
                    ${s.fatal}
                    EOF
                      chmod +x "$out/${name}/fatal"
                    ''}

                    ## reincarnation
                    ${lib.optionalString (s.finish != "") ''
                      cat > "$out/${name}/reincarnation" << 'EOF'
                    ${s.reincarnation}
                    EOF
                      chmod +x "$out/${name}/reincarnation"
                    ''}

                    ## log
                    ${lib.optionalString (s.log != null) ''
                      ln -s ${s.log} "$out/${name}/log"
                    ''}
                  '';
              in
              ''
                mkdir -p "$out"
                ${lib.concatMapStrings mkService svcList}
              ''
            );
          in
          {
            options = {
              services.nitroctl = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                  description = "Enable Nitro Supervisor.";
                };

                user = lib.mkOption {
                  type = lib.types.str;
                  default = "root";
                  description = "Nitro Supervisor User.";
                };

                group = lib.mkOption {
                  type = lib.types.str;
                  default = "nitro";
                  description = "Nitro Supervisor Group.";
                };

                path = lib.mkOption {
                  type = lib.types.str;
                  default = "/etc/nitro";
                  description = "Managed Services Location.";
                };

                services = lib.mkOption {
                  type = lib.types.attrsOf (
                    lib.types.submodule (
                      { name, ... }:
                      {
                        options = {
                          running = lib.mkOption {
                            type = lib.types.bool;
                            default = true;
                            description = ''
                              Whether this service should be brought up by default
                              (false corresponds to the presence of a `down` file).
                            '';
                          };

                          template = lib.mkOption {
                            type = lib.types.oneOf [
                              lib.types.bool
                              (lib.types.listOf lib.types.nonEmptyStr)
                            ];
                            default = false;
                            description = ''
                              If `true` or a list of strings, treat as Nitro template (appends '@' to dir name).
                              List creates symlinks: service@child -> service@.
                            '';
                          };

                          setup = lib.mkOption {
                            type = lib.types.str;
                            default = "";
                            description = ''
                              Optional executable script run before the service starts.
                              Must exit with status 0 to continue.
                            '';
                          };

                          run = lib.mkOption {
                            type = lib.types.str;
                            default = "";
                            description = ''
                              Optional executable script that runs the service; must not exit while the service is considered running.
                              If empty, the service is treated as a one-shot.
                            '';
                          };

                          finish = lib.mkOption {
                            type = lib.types.str;
                            default = "";
                            description = ''
                              Optional executable script run after the run process finishes.
                              Receives exit status and terminating signal as arguments.
                            '';
                          };

                          final = lib.mkOption {
                            type = lib.types.str;
                            default = "";
                            description = ''
                              Optional executable script for SYS
                              Runs after all services terminate.
                            '';
                          };

                          fatal = lib.mkOption {
                            type = lib.types.str;
                            default = "";
                            description = ''
                              Optional executable script for SYS
                              Runs if unrecoverable error occurs.
                            '';
                          };

                          reincarnation = lib.mkOption {
                            type = lib.types.str;
                            default = "";
                            description = ''
                              Optional executable script for SYS
                              Is executed into instead of a shutdown.
                            '';
                          };

                          log = lib.mkOption {
                            type = lib.types.nullOr lib.types.path;
                            default = null;
                            description = ''
                              Symlink target to another service directory whose stdin will receive this service's stdout for supervised logging.
                            '';
                          };
                        };
                      }
                    )
                  );
                  default = {
                    # === PRE-EXISTING SPECIAL SERVICES ===

                    # 1. Default LOG service (catch-all)
                    LOG = {
                      run = lib.mkDefault ''
                        #!/usr/bin/env bash
                        LOGFILE="/var/log/nitro/default.log"
                        mkdir -p "$(dirname "$LOGFILE")"
                        while IFS= read -r line || [[ -n "$line" ]]; do
                          echo "[$(date +'%%Y-%%m-%%dT%%H:%%M:%%S%%z')] $line" >> "$LOGFILE"
                        done
                      '';
                    };

                    # 2. LOG@ template (parameterized logging)
                    "LOG@" = {
                      template = lib.mkDefault true;
                      run = lib.mkDefault ''
                        #!/usr/bin/env bash
                        SERVICE_NAME="$1"
                        LOGFILE="/var/log/nitro/$SERVICE_NAME.log"
                        mkdir -p "$(dirname "$LOGFILE")"
                        while IFS= read -r line || [[ -n "$line" ]]; do
                          echo "[$(date +'%%Y-%%m-%%dT%%H:%%M:%%S%%z')] [$SERVICE_NAME] $line" >> "$LOGFILE"
                        done
                      '';
                    };

                    # 3. SYS service (system lifecycle)
                    SYS = {
                      setup = lib.mkDefault ''
                        #!/usr/bin/env bash
                        timeout 30 sh -c 'until ping -c1 8.8.8.8 >/dev/null 2>&1; do sleep 1; done' || true
                        mkdir -p /var/log/nitro /var/run/nitro
                        nitroctl up LOG
                        echo "SYS: Setup complete"
                      '';
                      finish = lib.mkDefault ''
                        #!/usr/bin/env bash
                        # SYS/finish: Graceful shutdown preparation
                        echo "SYS: Beginning shutdown sequence - $(date)"
                        sync
                      '';
                      final = lib.mkDefault ''
                        #!/usr/bin/env bash
                        # SYS/final: Post-termination cleanup
                        echo "SYS: Final cleanup - $(date)" > /var/log/nitro/final.log
                        sync
                      '';
                      fatal = lib.mkDefault ''
                        #!/usr/bin/env bash
                        # SYS/fatal: Unrecoverable error handler
                        # Log the panic
                        echo "FATAL ERROR at $(date)" > /var/log/nitro/fatal.log
                        echo "Nitro supervisor failed catastrophically" > /var/log/nitro/fatal.log
                        # Try graceful recovery first
                        if nitroctl restart SYS; then
                          echo "SYS: Recovered from fatal error" > /var/log/nitro/fatal.log
                          exit 0
                        fi
                        exec /bin/sh -l
                      '';
                      reincarnation = lib.mkDefault ''
                      '';
                    };
                  };
                  description = "Nitro services, keyed by service name.";
                };
              };
            };
            config = lib.mkIf cfg.enable {
              nixpkgs.overlays = [
                (final: prev: {
                  nitro = final.stdenv.mkDerivation rec {
                    pname = "nitro";
                    version = "v0.7.1";

                    src = final.fetchFromGitHub {
                      owner = "leahneukirchen";
                      repo = pname;
                      rev = version;
                      sha256 = "JnQ+xcYe36P0bdAlRd1bq7djNji2q0W0o7+bRPKCekY=";
                    };

                    installPhase = ''
                      mkdir -p $out/bin
                      install -m755 nitro $out/bin
                      install -m755 nitroctl $out/bin
                    '';

                    meta = with final.lib; {
                      description = "tiny but flexible init system and process supervisor";
                      homepage = "https://github.com/leahneukirchen/nitro";
                      license = licenses.cc0;
                      platforms = platforms.linux;
                    };
                  };
                })
              ];

              environment.systemPackages = [ pkgs.nitro ];

              users = {
                groups.${cfg.group} = {
                  name = cfg.group;
                  members = [
                    cfg.user
                    "root"
                  ];
                };
              };

              # Derive the etc key from cfg.path.
              environment.etc."${lib.removePrefix "/etc/" cfg.path}/services".source = servicesDir;

              fileSystems."/run/nitro" = {
                device = "tmpfs";
                fsType = "tmpfs";
              };

              systemd.tmpfiles.settings = {
                "21-nitro-run" = {
                  "/etc/${lib.removePrefix "/etc/" cfg.path}" = {
                    Z = {
                      mode = "0775";
                      user = cfg.user;
                      group = cfg.group;
                    };
                  };
                };
              };

              # systemd service running nitro
              systemd.services.nitro = {
                enable = true;
                description = "Nitro service supervisor";

                wantedBy = [ "default.target" ];
                after = [
                  "graphical-session.target"
                  "network.target"
                ];
                partOf = [ "graphical-session.target" ];

                serviceConfig = {
                  ExecStart = ''
                    ${pkgs.nitro}/bin/nitro /etc/${lib.removePrefix "/etc/" cfg.path}/services
                  '';
                  Restart = "always";
                  RestartSec = "15s";
                  User = cfg.user;
                  Group = cfg.group;
                  Environment = lib.concatStringsSep ":" [
                    "PATH=/run/current-system/sw/bin"
                    "/home/lantern/.nix-profile/bin"
                    "${pkgs.nitro}/bin"
                    "/usr/local/bin"
                    "/usr/bin"
                    "/bin"
                  ];
                };
              };
            };
          };
      };
    };
}
