"use hydration";

import { useState } from "hono/jsx";
import { rpc } from "/assets/client.rpc.ts";

type User = {
  id: number;
  name: string;
};

export default function RpcUsers() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [users, setUsers] = useState<User[] | null>(null);

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await rpc("UsersResource#rpc_index", undefined);
      setUsers(data as unknown as User[]);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
      <button type="button" onClick={load} disabled={loading}>
        {loading ? "Loading..." : "Fetch users via RPC"}
      </button>

      {error ? <pre style={{ whiteSpace: "pre-wrap" }}>{error}</pre> : null}

      {users ? (
        <ul>
          {users.map((u) => (
            <li key={u.id}>
              {u.id}: {u.name}
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}
