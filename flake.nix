{
  description = "NixOS modules for matrix related services";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs }: {
    nixosModules = {
      default = import ./module.nix;
    };

    lib = import ./lib.nix { lib = nixpkgs.lib; };

    packages = let
      forAllSystems = f:
        nixpkgs.lib.genAttrs [
          "x86_64-linux"
          "aarch64-linux"
          "x86_64-darwin"
          "aarch64-darwin"
        ] (system: f nixpkgs.legacyPackages.${system});
    in forAllSystems (pkgs: {
      tests = import ./tests {
        inherit nixpkgs pkgs;
        matrix-lib = self.lib;
      };
    });
  };
}
