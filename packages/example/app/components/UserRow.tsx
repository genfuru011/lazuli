type User = {
  id: number;
  name: string;
};

export default function UserRow(props: { user: User }) {
  return (
    <li id={`user_${props.user.id}`} class="user-row" style={{ display: "flex", gap: "8px" }}>
      <span style={{ flex: 1 }}>{props.user.id}: {props.user.name}</span>
      <a href={`/users/${props.user.id}`} data-turbo-method="delete">
        Delete
      </a>
    </li>
  );
}
