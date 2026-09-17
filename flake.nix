{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      perSystem = { pkgs, ... }: {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.chibi
            pkgs.curl
            pkgs.gnumake
            pkgs.coreutils
          ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.bubblewrap ];
        };
      };
    };
}
