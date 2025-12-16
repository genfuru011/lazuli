export default function UsersFooter(props: { count: number }) {
  return (
    <div id="users_footer" style={{ marginTop: "12px", fontSize: "12px", color: "#666" }}>
      Total users: {props.count}
    </div>
  );
}
