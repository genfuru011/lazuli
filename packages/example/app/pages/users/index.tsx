import Counter from "../../components/Counter.tsx";
import Island from "lazuli/island";
import UserRow from "../../components/UserRow.tsx";

type User = {
  id: number;
  name: string;
};

export default function UsersIndex(props: { users: User[] }) {
  return (
    <div>
      <h1>Users List</h1>

      <div id="flash" style={{ marginBottom: "12px" }}></div>

      <form method="post" action="/users" style={{ display: "flex", gap: "8px", marginBottom: "12px" }}>
        <input name="name" placeholder="Name" />
        <button type="submit">Add</button>
      </form>

      <ul id="users_list">
        {props.users.map((user) => (
          <UserRow user={user} key={user.id} />
        ))}
      </ul>

      <div style={{ "margin-top": "20px", border: "1px solid #ccc", padding: "10px" }}>
        <h3>Interactive Counter (Island)</h3>
        <Island 
          path="components/Counter" 
          component={Counter} 
          data={{ initialCount: 10 }} 
        />
      </div>
    </div>
  );
}
