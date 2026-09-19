const fs = require("node:fs");
const path = require("node:path");
const sharp = require("sharp");

const SIZE = 200;
const MAX_BYTES = 1_000_000;

async function main() {
  const sourcePath = path.resolve(process.argv[2]);
  const outputPath = path.resolve(process.argv[3]);

  if (!fs.existsSync(sourcePath)) {
    throw new Error(`Source image not found: ${sourcePath}`);
  }

  const { data, info } = await sharp(sourcePath, { failOn: "error" })
    .resize(SIZE, SIZE, {
      fit: "fill",
      kernel: sharp.kernel.lanczos3,
    })
    .removeAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  if (info.channels !== 3) {
    throw new Error(`Expected an RGB source after conversion, got ${info.channels} channels`);
  }

  // Steam preserves animated GIF previews. The second frame differs by one
  // practically invisible value in the bottom-right pixel, so the encoder
  // keeps two frames while the preview remains visually static.
  const secondFrame = Buffer.from(data);
  const lastPixel = secondFrame.length - info.channels;
  secondFrame[lastPixel] = secondFrame[lastPixel] === 255
    ? 254
    : secondFrame[lastPixel] + 1;

  const frames = Buffer.concat([data, secondFrame]);
  const temporaryPath = `${outputPath}.tmp.gif`;

  await sharp(frames, {
    raw: {
      width: SIZE,
      height: SIZE * 2,
      channels: info.channels,
      pageHeight: SIZE,
    },
  })
    .gif({
      colors: 256,
      dither: 1.0,
      effort: 10,
      loop: 0,
      delay: [1000, 1000],
      reuse: true,
    })
    .toFile(temporaryPath);

  const metadata = await sharp(temporaryPath, { animated: true }).metadata();
  const outputBytes = fs.statSync(temporaryPath).size;

  if (
    metadata.format !== "gif" ||
    metadata.width !== SIZE ||
    metadata.pageHeight !== SIZE ||
    metadata.pages !== 2
  ) {
    throw new Error(
      `Invalid output: format=${metadata.format}, width=${metadata.width}, ` +
      `pageHeight=${metadata.pageHeight}, pages=${metadata.pages}`,
    );
  }

  if (outputBytes >= MAX_BYTES) {
    throw new Error(`GIF is ${outputBytes} bytes; Steam limit is below ${MAX_BYTES} bytes`);
  }

  fs.copyFileSync(temporaryPath, outputPath);
  fs.unlinkSync(temporaryPath);

  console.log(`Created: ${outputPath}`);
  console.log(`GIF: ${SIZE}x${SIZE}, 2 frames, 256-color palette, ${outputBytes} bytes`);
}

main().catch((error) => {
  console.error(error.stack || error.message || String(error));
  process.exit(1);
});
