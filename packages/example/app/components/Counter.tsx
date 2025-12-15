"use hydration";

import { createSignal } from "solid-js";

export default function Counter(props: { initialCount: number }) {
  const [count, setCount] = createSignal(props.initialCount);
  
  return (
    <button onClick={() => setCount(c => c + 1)} class="btn">
      Count: {count()}
    </button>
  );
}
