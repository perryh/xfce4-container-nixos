# WhiteSur GTK theme, from the prebuilt release tarball shipped in the pinned tag.
# The Ubuntu repo cloned the same ref and extracted release/WhiteSur-Light.tar.xz
# into /usr/share/themes; this does the same, plus the Plank theme link the dock
# needs (plank looks themes up under <datadir>/plank/themes).
{ stdenv, fetchFromGitHub, xz }:

stdenv.mkDerivation {
  pname = "whitesur-gtk-theme";
  version = "2026-09-10";

  src = fetchFromGitHub {
    owner = "vinceliuice";
    repo = "WhiteSur-gtk-theme";
    # Tag 2026-09-10, pinned to its commit.
    rev = "99247ecd219bdc1c7409baff062b4aafcf1102a7";
    hash = "sha256-yr22QbqoZFp/Kwx1jVMO78SMBRumtdWEOpO/YXijQZU=";
  };

  nativeBuildInputs = [ xz ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/themes $out/share/plank/themes
    tar -xJf release/WhiteSur-Light.tar.xz -C $out/share/themes
    ln -s ../../themes/WhiteSur-Light/plank $out/share/plank/themes/WhiteSur-Light
    runHook postInstall
  '';
}
