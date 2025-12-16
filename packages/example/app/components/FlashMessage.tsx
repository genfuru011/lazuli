export default function FlashMessage(props: { message: string }) {
  return <div style={{ padding: "8px", background: "#f5f5f5", border: "1px solid #ddd" }}>{props.message}</div>;
}
