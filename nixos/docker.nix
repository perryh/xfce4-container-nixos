# Nested Docker: the container is launched with security.nesting=true, so Docker
# runs inside the unprivileged container, as in the Ubuntu repo.
{ lib, pkgs, ... }:

{
  virtualisation.docker.enable = true;
  environment.systemPackages = [ pkgs.docker-compose ];
}
