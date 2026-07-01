{
  description = "cardano-kupo";

  inputs = {
    kupo = {
      url = "github:CardanoSolutions/kupo/3944e069f199339d35e97684fdbdb425d6178c25";
      flake = false;
    };
    haskellNix = {
      url = "github:input-output-hk/haskell.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    CHaP = {
      url = "github:intersectMBO/cardano-haskell-packages/repo";
      flake = false;
    };
    iohkNix = {
      url = "github:input-output-hk/iohk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    config.url = "github:input-output-hk/empty-flake";
  };

  outputs = { self, kupo, iohkNix, haskellNix, CHaP, nixpkgs, flake-utils, config, ... }:
    let
      inherit (nixpkgs) lib;
      inherit (flake-utils.lib) eachSystem flattenTree;
      inherit (iohkNix.lib) evalService;

      supportedSystems = config.supportedSystems or (import ./nix/supported-systems.nix);

      # Kupo repo still declares the cardano-haskell-packages repository using the legacy iohk url
      inputMap = { "https://input-output-hk.github.io/cardano-haskell-packages" = CHaP; };

      overlay = final: prev: {
        kupoHaskellProject = self.legacyPackages.${final.system};
        inherit (final.cardanoKupoHaskellProject.hsPkgs.kupo.exes) kupo;
      };

    in
    eachSystem supportedSystems
      (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            inherit (haskellNix) config;
            overlays = [
              iohkNix.overlays.crypto
              haskellNix.overlay
              iohkNix.overlays.haskell-nix-extra
              iohkNix.overlays.haskell-nix-crypto
              iohkNix.overlays.cardano-lib
              iohkNix.overlays.utils
              overlay
            ];
          };

          project = (import ./nix/haskell.nix pkgs.haskell-nix kupo inputMap).appendModule (config.haskellNix or { });

          # scripts = flattenTree (import ./nix/scripts.nix {
          #   inherit project evalService;
          #   customConfigs = [ config ];
          # });

          packages = {
            inherit (project.hsPkgs.kupo.components.exes) kupo;
          }; # // scripts;

          apps = lib.mapAttrs (n: p: { type = "app"; program = p.exePath or "${p}/bin/${p.name or n}"; }) packages;

        in
        {

          inherit packages apps project;

          legacyPackages = project;

          # Built by `nix build .`
          defaultPackage = packages.kupo;

          # Run by `nix run .`
          defaultApp = apps.kupo;
        }
      ) // {
      inherit overlay; #nixosModule;
      hydraJobs = self.packages // {
        required = with self.legacyPackages.${lib.head supportedSystems}.pkgs; releaseTools.aggregate {
          name = "github-required";
          meta.description = "All jobs required to pass CI";
          constituents = lib.collect lib.isDerivation self.packages ++ lib.singleton
            (writeText "forceNewEval" self.rev or "dirty");
        };
      };
    };

  nixConfig = {
    extra-substituters = [ "https://cache.iog.io" ];
    extra-trusted-public-keys = [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];
    allow-import-from-derivation = true;
  };
}
