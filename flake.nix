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
                mkService =
                  svc:
                  let
                    name = svc.name;
                    s = svc.value;
                  in
                  ''
                    mkdir -p "$out/${name}"

                    # running -> presence/absence of 'down'
                    ${lib.optionalString (!s.running) ''
                      touch "$out/${name}/down"
                    ''}

                    # setup script
                    ${lib.optionalString (s.setup != "") ''
                                  cat > "$out/${name}/setup" << 'EOF'
                      ${s.setup}
                      EOF
                                  chmod +x "$out/${name}/setup"
                    ''}

                    # run script
                    ${lib.optionalString (s.run != "") ''
                                  cat > "$out/${name}/run" << 'EOF'
                      ${s.run}
                      EOF
                                  chmod +x "$out/${name}/run"
                    ''}

                    # finish script
                    ${lib.optionalString (s.finish != "") ''
                                  cat > "$out/${name}/finish" << 'EOF'
                      ${s.finish}
                      EOF
                                  chmod +x "$out/${name}/finish"
                    ''}

                    # log symlink
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

                # user = lib.mkOption {
                #   type = lib.types.str;
                #   default = "nitro";
                #   description = "Nitro Supervisor User.";
                # };

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
                  default = { };
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
                    "root"
                  ];
                };
              };

              # Derive the etc key from cfg.path.
              environment.etc."${lib.removePrefix "/etc/" cfg.path}/services".source = servicesDir;

              systemd.tmpfiles.settings = {
                "21-nitro-run" = {
                  "/etc/${lib.removePrefix "/etc/" cfg.path}" = {
                    Z = {
                      mode = "0775";
                      user = "root";
                      group = cfg.group;
                    };
                  };
                  "/run/nitro" = {
                    z = {
                      mode = "0775";
                      user = "root";
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
                  ExecStart = "${pkgs.nitro}/bin/nitro /etc/${lib.removePrefix "/etc/" cfg.path}/services";
                  Restart = "always";
                  RestartSec = "15s";
                  User = "root";
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
