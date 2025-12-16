export default function Notice(props: { message: string }) {
  return (
    <div id="notice" style={{ padding: "8px", background: "#fff7d6", border: "1px solid #e0c46c", marginBottom: "12px" }}>
      {props.message}
    </div>
  );
}
