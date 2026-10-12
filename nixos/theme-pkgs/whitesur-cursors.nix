# WhiteSur cursors, from the same pinned commit the Ubuntu repo used. Upstream
# ships the built theme under dist/, so there is nothing to build.
{ stdenv, fetchFromGitHub }:

stdenv.mkDerivation {
  pname = "whitesur-cursors";
  version = "0-unstable";

  src = fetchFromGitHub {
    owner = "vinceliuice";
    repo = "WhiteSur-cursors";
    rev = "e190baf618ed95ee217d2fd45589bd309b37672b";
    hash = "sha256-hFtfq8F6KeqUEBlypPCr/EKq6rif/g868vJd8c06c1I=";
  };

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/icons
    cp -r dist $out/share/icons/WhiteSur-cursors
    runHook postInstall
  '';
}
