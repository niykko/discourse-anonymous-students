# name: discourse-anonymous-students
# about: Intercepts student posts in a specific category and remaps them to a single anonymous user to prevent database bloat.
# version: 1.0.0
# authors: Pretty much AI 

# Tell Discourse about our toggle switch
enabled_site_setting :anonymous_students_enabled

register_asset "stylesheets/anonymous-students.scss"
register_asset "javascripts/discourse/initializers/anonymous-students.js.es6"

after_initialize do
  # 1. Register the custom field so Discourse knows it is allowed in the database
  Post.register_custom_field_type('true_author_id', :integer)
  Post.register_custom_field_type('true_author_username', :string)

  # 2. Expose the hidden audit trail to staff via post serializer fields
  add_to_serializer(:post, :true_author_id) do
    next unless scope.is_staff?
    object.custom_fields['true_author_id']
  end

  add_to_serializer(:post, :true_author_username) do
    next unless scope.is_staff?
    object.custom_fields['true_author_username']
  end

  # 3. Hook into the post creation process right before it saves to the database
  on(:before_create_post) do |post|
    # Skip immediately if you have disabled the plugin in the admin panel
    next unless SiteSetting.anonymous_students_enabled
    
    # Grab the target category ID from your admin settings
    target_category_id = SiteSetting.anonymous_students_category_id.to_i
    
    # Determine the category of the incoming post
    post_category_id = post.topic&.category_id

    # Skip if we are not in the designated anonymous category
    next unless post_category_id == target_category_id
    
    # Check who is trying to post
    original_user = post.user
    next unless original_user

    # Skip if the user is a staff member (Admin/Moderator)
    # This ensures your professors ALWAYS post with their real names and flairs
    next if original_user.staff?

    # Fetch the designated anonymous account based on the admin setting
    anon_user = User.find_by(username: SiteSetting.anonymous_students_username)

    # Safety check: If the anonymous bot account doesn't exist, do not break the forum (just skip)
    next unless anon_user

    # 3. The Swap
    # Save the real student's User ID into the hidden custom field for your admin audit trail
    post.custom_fields['true_author_id'] = original_user.id
    post.custom_fields['true_author_username'] = original_user.username

    # Change the author of the post to the single bot account
    post.user = anon_user
    post.user_id = anon_user.id
    
    # CRITICAL: Prevent the student's name from leaking on the category topic list
    if post.is_first_post? && post.topic
      post.topic.user = anon_user
      post.topic.user_id = anon_user.id
      
      # Optional Bonus: Automatically make the real student "Watch" the topic 
      # so they get email notifications when professors reply to their anonymous question!
      TopicUser.change(original_user.id, post.topic.id, notification_level: TopicUser.notification_levels[:watching])
    end
  end
end
