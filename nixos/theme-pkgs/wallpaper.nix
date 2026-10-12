# Generated wallpaper: a soft three-stop gradient, so no image is downloaded.
# Deterministic, so the same derivation hash comes out on every machine.
{ runCommand, ffmpeg-headless }:

runCommand "xfce4-container-wallpaper.png"
{
  nativeBuildInputs = [ ffmpeg-headless ];
}
''
  ffmpeg -loglevel error -y -f lavfi \
    -i "gradients=s=1920x1200:n=3:c0=0x4a78d8:c1=0x9a7fd1:c2=0xf0a8c4:x0=0:y0=0:x1=1920:y1=1200" \
    -frames:v 1 "$out"
''
