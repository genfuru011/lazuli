import Counter from "../../components/Counter.tsx";
import Island from "lazuli/island";

type User = {
  id: number;
  name: string;
};

export default function UsersIndex(props: { users: User[] }) {
  return (
    <div>
      <h1>Users List</h1>
      <ul>
        {props.users.map((user) => (
          <li>
            {user.id}: {user.name}
          </li>
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
