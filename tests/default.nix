{ nixpkgs, pkgs, matrix-lib, ... }:
{
  nginx-pipeline-eval = pkgs.callPackage ./nginx-pipeline { inherit nixpkgs matrix-lib; };

  synapse = pkgs.testers.runNixOSTest ./synapse;
}
