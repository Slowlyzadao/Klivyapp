import fetch from 'node-fetch';

async function testSend() {
  const res = await fetch('http://localhost:3002/sessions/10/send', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      to: '158004551722830@s.whatsapp.net',
      type: 'audio',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3'
    })
  });
  const text = await res.text();
  console.log(text);
}
testSend();
