# Nitro Flake: Add and Manage Nitro & Nitroctl using NixOS


## Features

- Installs a nitro/ctl package derivation
- Custom nitro services location
- Supports enabling/disabling each service by default

## Usage

1. Add the flake to your nix config inputs:
```
inputs = {
  nitro-flake.url = "github:Jack-Chronicle/nitro-flake";
};
```

2. Include the module in your nixos configuration:
```
imports = [
  inputs.nitro-flake.nixosModules.default
];
```

# Default Configuration Options

```
{
  services = {
    nitroctl = {
      enable = true; # Enable nitro & nitroctl packages
      group = "nitro"; # Group to Run service as
      path = "/etc/nitro"; # Services Location
      services = {
        "service-name" = {
          running = bool; # boolean; true/false
          setup = multiline string; # ''text block''
          run = multiline string; # ''text block''
          finish = multiline string; # ''text block''
          log = path; # absolute path to log service
        };
      };
    };
  };
}
```

## Service Descriptions

- `running` (down)
  an optional file that causes nitro to not bring up this service by default.
- `setup`
  an optional executable file that is run before the service starts. It must exit with status 0 to continue.
- `run`
  an optional executable file that runs the service; it must not exit as long as the service is considered running. If there is no run script, the service is considered a "one shot", and stays "up" until it's explicitly taken "down".
- `finish`
  an optional executable file that is run after the run process finished. It is passed two arguments, the exit status of the run process (or -1 if it was killed by a signal) and the signal that killed it (or 0, if it exited regularly).
- `log`
  a symlink to another service directory. The standard output of run is connected to the standard input of the service under log by a pipe. You can chain these for reliable and supervised log processing.
