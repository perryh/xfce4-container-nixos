# WhiteSur icon theme, installed with upstream's install.sh exactly like the
# Ubuntu repo did:  ./install.sh -d <icons dir> -t default
{ stdenv, fetchFromGitHub, gtk3 }:

stdenv.mkDerivation {
  pname = "whitesur-icon-theme";
  version = "2026-09-10";

  src = fetchFromGitHub {
    owner = "vinceliuice";
    repo = "WhiteSur-icon-theme";
    # Tag 2026-09-10, pinned to its commit.
    rev = "73d8040da51a9ed74e47c7366e7e9ff437601a5c";
    hash = "sha256-LeSXzFZK12Q0MVG7OxijRF3OJC6EsFx7ehg9iRp75ac=";
  };

  nativeBuildInputs = [ gtk3 ];

  installPhase = ''
    runHook preInstall
    export HOME=$(mktemp -d)
    patchShebangs .
    # -n: stdenv exports $name into the environment, which would otherwise win
    # over the script's default theme name.
    ./install.sh -d $out/share/icons -n WhiteSur -t default
    runHook postInstall
  '';
}
