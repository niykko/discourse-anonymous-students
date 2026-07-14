# name: discourse-anonymous-students
# about: Intercepts student posts in selected categories and remaps them to a single anonymous user to prevent database bloat.
# version: 1.2.1
# authors: niykko + AI

# Tell Discourse about our toggle switch
enabled_site_setting :anonymous_students_enabled

register_asset "stylesheets/anonymous-students.scss"

after_initialize do
  # 1. Register custom fields to store the real author securely
  Post.register_custom_field_type('true_author_id', :integer)
  Post.register_custom_field_type('true_author_username', :string)

  add_to_serializer(:post, :true_author_id) do
    next unless scope.is_staff?
    object.custom_fields['true_author_id']
  end

  add_to_serializer(:post, :true_author_username) do
    next unless scope.is_staff?
    object.custom_fields['true_author_username']
  end

  # Publicly expose only whether this post came from the topic's original
  # student author. The author's identity remains available to staff only.
  add_to_serializer(:post, :anonymous_students_original_poster) do
    true_author_id = object.custom_fields['true_author_id']
    next false if true_author_id.blank?

    if object.post_number == 1
      true
    else
      # Topic pages share one TopicView across their post serializers, so use it
      # to avoid repeating this lookup for every reply. A standalone post
      # response performs only one lookup and can use a local hash.
      original_author_ids =
        if @topic_view
          @topic_view.instance_variable_get(:@anonymous_students_original_author_ids) ||
            @topic_view.instance_variable_set(:@anonymous_students_original_author_ids, {})
        else
          {}
        end
      original_author_id =
        original_author_ids.fetch(object.topic_id) do
          original_author_ids[object.topic_id] =
            ::PostCustomField
              .joins(:post)
              .where(
                name: 'true_author_id',
                posts: { topic_id: object.topic_id, post_number: 1 }
              )
              .pick(:value)
        end

      original_author_id.present? && true_author_id.to_i == original_author_id.to_i
    end
  end

  # 2. Intercept PostCreator directly
  module ::AnonymousStudentPostCreator
    def initialize(user, opts)
      @true_author = nil
      category_ids =
        (SiteSetting.anonymous_students_category_id.presence || "").split("|").map(&:to_i)

      # Figure out if this post/topic is destined for an anonymous category
      is_anon_category = false
      if category_ids.include?(opts[:category].to_i) || category_ids.include?(opts[:category_id].to_i)
        is_anon_category = true
      elsif opts[:topic_id].present?
        # If it's a reply, check the parent topic's category
        topic = Topic.find_by(id: opts[:topic_id])
        is_anon_category = category_ids.include?(topic&.category_id)
      end

      # If conditions are met, swap the user at the front door!
      if SiteSetting.anonymous_students_enabled && is_anon_category && !user.staff?
        anon_user = User.find_by(username: SiteSetting.anonymous_students_username)
        if anon_user
          @true_author = user # Save the real user in an instance variable for later
          user = anon_user    # Replace the user Discourse sees with the Bot!
        end
      end

      # Continue normal Discourse initialization, but with the Bot as the user
      super(user, opts)
    end

    def create
      # Let Discourse do its massive, complex creation process natively
      post = super
      
      # After it safely finishes, apply our custom logic
      if @true_author && post && post.persisted?
        # Save the hidden audit trail to the database
        post.custom_fields['true_author_id'] = @true_author.id
        post.custom_fields['true_author_username'] = @true_author.username
        post.save_custom_fields(true)

        # Force the original student to "Watch" their own topic so they get notifications
        if post.is_first_post?
          TopicUser.change(
            @true_author.id, 
            post.topic_id, 
            notification_level: TopicUser.notification_levels[:watching]
          )
        end
      end
      
      post
    end
  end
  
  # Inject our wrapper around Discourse's native PostCreator
  ::PostCreator.prepend(::AnonymousStudentPostCreator)
end
