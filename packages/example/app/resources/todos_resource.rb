require_relative "../repositories/todo_repository"

class TodosResource < Lazuli::Resource
  def index
    todos = TodoRepository.all
    Render "todos", todos: todos, count: todos.length
  end

  def create
    text = params[:text].to_s.strip
    return redirect("/todos") if text.empty?

    TodoRepository.create(text: text)
    redirect("/todos")
  end

  def create_stream
    text = params[:text].to_s.strip
    if text.empty?
      return stream do |t|
        t.update "flash", "components/FlashMessage", message: "Text is required"
      end
    end

    todo = TodoRepository.create(text: text)

    stream do |t|
      t.prepend "todos_list", "components/TodoRow", todo: todo
      t.replace "todos_footer", "components/TodosFooter", count: TodoRepository.count
      t.update "flash", "components/FlashMessage", message: "Added todo ##{todo.id}"
    end
  end

  def update
    TodoRepository.toggle(params[:id])
    redirect("/todos")
  end

  def update_stream
    todo = TodoRepository.toggle(params[:id])
    unless todo
      return stream do |t|
        t.update "flash", "components/FlashMessage", message: "Todo not found: #{params[:id]}"
      end
    end

    stream do |t|
      t.replace "todo_#{params[:id]}", "components/TodoRow", todo: todo
      t.update "flash", "components/FlashMessage", message: "Toggled todo ##{params[:id]}"
    end
  end

  def destroy
    if params[:id]
      TodoRepository.delete(params[:id])
      return redirect("/todos")
    end

    TodoRepository.clear
    redirect("/todos")
  end

  def destroy_stream
    if params[:id]
      TodoRepository.delete(params[:id])

      return stream do |t|
        t.remove "todo_#{params[:id]}"
        t.replace "todos_footer", "components/TodosFooter", count: TodoRepository.count
        t.update "flash", "components/FlashMessage", message: "Deleted todo ##{params[:id]}"
      end
    end

    TodoRepository.clear

    stream do |t|
      t.remove "#todos_list li"
      t.replace "todos_footer", "components/TodosFooter", count: 0
      t.update "flash", "components/FlashMessage", message: "Deleted all todos via targets"
    end
  end
end
