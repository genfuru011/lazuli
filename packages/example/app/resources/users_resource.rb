class UsersResource < Lazuli::Resource
  rpc :rpc_index, returns: [User]

  def index
    users = UserRepository.all
    Render "users/index", users: users
  end

  def rpc_index
    UserRepository.all
  end

  def create
    UserRepository.create(name: params[:name].to_s)
    redirect("/users")
  end

  def create_stream
    user = UserRepository.create(name: params[:name].to_s)

    stream do |t|
      # Show prepend + before/after in one place.
      t.prepend "users_list", "components/UserRow", user: user

      t.remove "notice"
      t.before "users_list", "components/Notice", message: "Added #{user.name}"

      t.remove "users_footer"
      t.after "users_list", "components/UsersFooter", count: UserRepository.all.length

      t.update "flash", "components/FlashMessage", message: "Turbo Streams: prepend + before/after"
    end
  end

  def destroy
    if params[:id]
      UserRepository.delete(params[:id])
      return redirect("/users")
    end

    UserRepository.clear
    redirect("/users")
  end

  def destroy_stream
    if params[:id]
      user = UserRepository.delete(params[:id])

      return stream do |t|
        t.remove "user_#{params[:id]}"

        t.remove "notice"
        t.before "users_list", "components/Notice", message: "Deleted #{user&.name || params[:id]}"

        t.remove "users_footer"
        t.after "users_list", "components/UsersFooter", count: UserRepository.all.length

        t.replace "flash", "components/FlashBox", message: "Deleted #{user&.name || params[:id]}"
      end
    end

    # DELETE /users -> batch delete demo (targets)
    UserRepository.clear

    stream do |t|
      t.remove "#users_list li"
      t.remove "notice"
      t.remove "users_footer"
      t.after "users_list", "components/UsersFooter", count: 0
      t.update "flash", "components/FlashMessage", message: "Deleted all users via targets"
    end
  end
end
