export default function FlashBox(props: { message: string }) {
  return (
    <div id="flash" style={{ padding: "8px", background: "#f5f5f5", border: "1px solid #ddd" }}>
      {props.message}
    </div>
  );
}
