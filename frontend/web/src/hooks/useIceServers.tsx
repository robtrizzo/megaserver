import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api";

export const iceServersQueryOptions = {
  queryKey: ["ice-servers"] as const,
  queryFn: api.getIceServers,
  staleTime: 1000 * 60 * 60, // 1 hour
};

export function useIceServers() {
  return useQuery(iceServersQueryOptions);
}
