# name: discourse-anonymous-students
# about: Intercepts student posts in a specific category and remaps them to a single anonymous user to prevent database bloat.
# version: 1.0.0
# authors: Pretty much AI 

# Tell Discourse about our toggle switch
enabled_site_setting :anonymous_students_enabled

register_asset "stylesheets/anonymous-students.scss"

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

  # Hook into the post creation process right before it saves to the database
  on(:before_create_post) do |post|
    begin
      next unless SiteSetting.anonymous_students_enabled
      
      target_category_id = SiteSetting.anonymous_students_category_id.to_i
      post_category_id = post.topic&.category_id

      # Only run this logic inside our specific anonymous category
      next unless post_category_id == target_category_id
      
      original_user = post.user
      next unless original_user
      next if original_user.staff? # Keep staff members visible for transparency

      anon_user = User.find_by(username: SiteSetting.anonymous_students_username)
      next unless anon_user

      # 1. Store the true author information securely in hidden custom fields
      post.custom_fields['true_author_id'] = original_user.id
      post.custom_fields['true_author_username'] = original_user.username

      # 2. Swap out the post author with our purely internal bot account
      post.user_id = anon_user.id
      post.user = anon_user
      
      # 3. If this is the brand-new first post of a topic, clean up the topic wrapper
      if post.is_first_post? && post.topic
        
        # FIX 1: Update the in-memory object! If not done, PostCreator 
        # will overwrite the database with the original user on its final save.
        post.topic.user_id = anon_user.id
        post.topic.user = anon_user
        
        # Keep the update_columns as a safety net for immediate DB state
        post.topic.update_columns(user_id: anon_user.id)
        
        # FIX 2: Revert to passing the integer ID. Passing the object crashes the block.
        TopicUser.change(original_user.id, post.topic.id, notification_level: TopicUser.notification_levels[:watching])
      end
    rescue => e
      # Safety catch: If anything goes wrong, write it cleanly to Discourse error logs
      Rails.logger.error("[PLUGIN anonymous-students] Post swap failed: #{e.message}\n#{e.backtrace.join("\n")}")
    end
  end
end
