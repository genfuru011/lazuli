class UsersResource < Lazuli::Resource
  def index
    users = UserRepository.all
    Render "users/index", users: users
  end

  def create
    user = UserRepository.create(name: params[:name].to_s)

    if turbo_stream?
      return turbo_stream do |t|
        t.append "users_list", fragment: "components/UserRow", props: { user: user }
        t.update "flash", fragment: "components/FlashMessage", props: { message: "Added #{user.name}" }
      end
    end

    redirect_to "/users"
  end

  def destroy
    user = UserRepository.delete(params[:id])

    if turbo_stream?
      return turbo_stream do |t|
        t.remove "user_#{params[:id]}"
        t.replace "flash", fragment: "components/FlashBox", props: { message: "Deleted #{user&.name || params[:id]}" }
      end
    end

    redirect_to "/users"
  end
end
