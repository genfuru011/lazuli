class UsersResource < Lazuli::Resource
  def index
    users = UserRepository.all
    Render "users/index", users: users
  end

  def create
    user = UserRepository.create(name: params[:name].to_s)

    if turbo_stream?
      return turbo_stream do |t|
        # Show prepend + before/after in one place.
        t.prepend "users_list", fragment: "components/UserRow", props: { user: user }

        t.remove "notice"
        t.before "users_list", fragment: "components/Notice", props: { message: "Added #{user.name}" }

        t.remove "users_footer"
        t.after "users_list", fragment: "components/UsersFooter", props: { count: UserRepository.all.length }

        t.update "flash", fragment: "components/FlashMessage", props: { message: "Turbo Streams: prepend + before/after" }
      end
    end

    redirect_to "/users"
  end

  def destroy
    user = UserRepository.delete(params[:id])

    if turbo_stream?
      return turbo_stream do |t|
        t.remove "user_#{params[:id]}"

        t.remove "notice"
        t.before "users_list", fragment: "components/Notice", props: { message: "Deleted #{user&.name || params[:id]}" }

        t.remove "users_footer"
        t.after "users_list", fragment: "components/UsersFooter", props: { count: UserRepository.all.length }

        t.replace "flash", fragment: "components/FlashBox", props: { message: "Deleted #{user&.name || params[:id]}" }
      end
    end

    redirect_to "/users"
  end
end
