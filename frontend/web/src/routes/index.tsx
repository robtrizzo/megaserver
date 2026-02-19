import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import { init, startLocalStream, call, cleanup } from "../lib/rtc";
import { Button } from "@/components/ui/button";

export const Route = createFileRoute("/")({ component: App });

function App() {
  const localVideoRef = useRef<HTMLVideoElement>(null);
  const remoteVideoRef = useRef<HTMLVideoElement>(null);
  const [isStreaming, setIsStreaming] = useState(false);

  useEffect(() => {
    if (remoteVideoRef.current) {
      init(remoteVideoRef.current, "ws://localhost:8080");
    }
    return () => cleanup();
  }, []);

  const handleStart = async () => {
    if (localVideoRef.current) {
      await startLocalStream(localVideoRef.current);
      setIsStreaming(true);
    }
  };

  const handleCall = async () => {
    await call();
  };

  const handleHangup = () => {
    cleanup();
    if (remoteVideoRef.current) {
      init(remoteVideoRef.current, "ws://localhost:8080");
    }
    setIsStreaming(false);
  };

  return (
    <div className="min-h-screen bg-linear-to-b from-slate-900 via-slate-800 to-slate-900 flex flex-col items-center gap-4 p-4">
      <div className="w-full flex justify-center">
        <video
          ref={localVideoRef}
          autoPlay
          playsInline
          muted
          className="w-80 rounded-sm border-2"
        />
        <video
          ref={remoteVideoRef}
          autoPlay
          playsInline
          className="w-80 rounded-sm border-2"
        />
      </div>
      <div className="flex gap-2">
        {isStreaming ? (
          <Button onClick={handleHangup} variant="destructive">
            Hangup
          </Button>
        ) : (
          <Button onClick={handleStart}>Start Camera</Button>
        )}
        <Button onClick={handleCall} variant="secondary">
          Call
        </Button>
      </div>
    </div>
  );
}
