let pc: RTCPeerConnection | null = null;
let localStream: MediaStream | null = null;
let signalingServer: WebSocket | null = null;

// --- 1. Initialize the connection ---
export function init(remoteVideo: HTMLVideoElement, signalingUrl: string) {
  // Connect to your signaling server
  signalingServer = new WebSocket(signalingUrl);

  // Create peer connection
  pc = new RTCPeerConnection({
    iceServers: [{ urls: "stun:stun.l.google.com:19302" }],
  });

  // When remote tracks arrive, display them
  pc.ontrack = (event) => {
    remoteVideo.srcObject = event.streams[0];
  };

  // Send ICE candidates to the other peer via signaling server
  pc.onicecandidate = (event) => {
    if (event.candidate) {
      signalingServer!.send(
        JSON.stringify({ type: "ice-candidate", candidate: event.candidate }),
      );
    }
  };

  // Handle messages from signaling server
  signalingServer.onmessage = async (msg) => {
    const data = JSON.parse(msg.data);

    if (data.type === "offer") {
      await pc!.setRemoteDescription(new RTCSessionDescription(data.sdp));
      const answer = await pc!.createAnswer();
      await pc!.setLocalDescription(answer);
      signalingServer!.send(JSON.stringify({ type: "answer", sdp: answer }));
    } else if (data.type === "answer") {
      await pc!.setRemoteDescription(new RTCSessionDescription(data.sdp));
    } else if (data.type === "ice-candidate") {
      await pc!.addIceCandidate(new RTCIceCandidate(data.candidate));
    }
  };
}

// --- 2. Add local camera to the connection ---
export async function startLocalStream(localVideo: HTMLVideoElement) {
  localStream = await navigator.mediaDevices.getUserMedia({
    video: true,
    audio: true,
  });
  localVideo.srcObject = localStream;
  localStream.getTracks().forEach((track) => pc!.addTrack(track, localStream!));
}

export async function endLocalStream() {
  localStream?.getTracks().forEach((track) => track.stop());
  localStream = null;
}

// --- 3. Caller creates and sends an offer ---
export async function call() {
  const offer = await pc!.createOffer();
  await pc!.setLocalDescription(offer);
  signalingServer!.send(JSON.stringify({ type: "offer", sdp: offer }));
}

// --- 4. Cleanup ---
export function cleanup() {
  endLocalStream();
  pc?.close();
  signalingServer?.close();
  pc = null;
  signalingServer = null;
}

// Minimal signaling server using the built-in WebSocket support
// (e.g., with Bun, Deno, or a simple Node.js ws server)

// Pseudocode:
// 1. User A connects to signaling server
// 2. User B connects to signaling server
// 3. User A creates an RTCPeerConnection and an SDP offer → sends to server
// 4. Server forwards the offer to User B
// 5. User B creates an RTCPeerConnection, sets the offer, creates an SDP answer → sends to server
// 6. Server forwards the answer to User A
// 7. Both sides exchange ICE candidates through the server
// 8. Direct peer-to-peer connection is established
