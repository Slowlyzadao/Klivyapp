// Pipeline client-side de figurinhas:
// arquivo PNG/JPG/GIF/WebP → canvas (preserva aspect ratio dentro de MAX_SIZE)
// → exporta WebP comprimido. Reduz upload de fotos 4MP pra ~30-100KB.

const MAX_SIZE = 512;
const TARGET_QUALITY = 0.85;
const TARGET_TYPE = 'image/webp';

const ACCEPT_INPUT_TYPES = /^image\/(png|jpe?g|gif|webp)$/i;
const MAX_INPUT_BYTES = 8 * 1024 * 1024; // 8MB no input cru — depois cai pra <300KB

const MIN_DIM = 32; // imagem ridiculamente pequena rejeita
const MAX_OUT_BYTES = 300 * 1024; // limite que o backend valida também

const loadImage = file =>
  new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve(img);
    };
    img.onerror = err => {
      URL.revokeObjectURL(url);
      reject(err);
    };
    img.src = url;
  });

const canvasToBlob = (canvas, type, quality) =>
  new Promise(resolve => canvas.toBlob(resolve, type, quality));

export async function processStickerFile(file) {
  if (!file) throw new Error('Selecione uma imagem.');
  if (!ACCEPT_INPUT_TYPES.test(file.type)) {
    throw new Error('Use PNG, JPG, GIF ou WebP.');
  }
  if (file.size > MAX_INPUT_BYTES) {
    throw new Error('Imagem muito grande (máximo 8MB).');
  }

  const img = await loadImage(file);
  if (img.width < MIN_DIM || img.height < MIN_DIM) {
    throw new Error('Imagem muito pequena.');
  }

  const ratio = Math.min(MAX_SIZE / img.width, MAX_SIZE / img.height, 1);
  const w = Math.round(img.width * ratio);
  const h = Math.round(img.height * ratio);

  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d');
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(img, 0, 0, w, h);

  // Tenta WebP primeiro; se o browser não suportar, cai pra PNG.
  let blob = await canvasToBlob(canvas, TARGET_TYPE, TARGET_QUALITY);
  if (!blob) blob = await canvasToBlob(canvas, 'image/png');
  if (!blob) throw new Error('Falha ao converter imagem.');

  // Se ainda passar do limite, reduz qualidade progressivamente.
  let quality = TARGET_QUALITY;
  while (blob.size > MAX_OUT_BYTES && quality > 0.5) {
    quality -= 0.1;
    blob = await canvasToBlob(canvas, TARGET_TYPE, quality);
    if (!blob) break;
  }
  if (blob && blob.size > MAX_OUT_BYTES) {
    throw new Error('Não foi possível compactar abaixo de 300KB.');
  }

  return { blob, width: w, height: h };
}

export const STICKER_INPUT_ACCEPT = 'image/png,image/jpeg,image/gif,image/webp';
