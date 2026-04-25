import fetch from 'node-fetch';

async function testFetch() {
  try {
    const res = await fetch('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3');
    console.log(res.status);
    console.log(res.ok);
  } catch (err) {
    console.error(err);
  }
}
testFetch();
