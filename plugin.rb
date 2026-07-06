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

  # 3. INTERCEPT TOPICS: Swap the owner of the topic wrapper before it is ever saved
  add_model_callback(:topic, :before_create) do
    begin
      next unless SiteSetting.anonymous_students_enabled
      next unless self.category_id == SiteSetting.anonymous_students_category_id.to_i
      
      original_user = self.user
      next unless original_user
      next if original_user.staff?

      anon_user = User.find_by(username: SiteSetting.anonymous_students_username)
      if anon_user
        self.user_id = anon_user.id
        self.user = anon_user
      end
    rescue => e
      Rails.logger.error("[PLUGIN anonymous-students] Topic swap failed: #{e.message}")
    end
  end

  # 4. INTERCEPT POSTS: Swap the owner of the post (handles replies AND first post bodies)
  on(:before_create_post) do |post|
    begin
      next unless SiteSetting.anonymous_students_enabled
      next unless post.topic&.category_id == SiteSetting.anonymous_students_category_id.to_i
      
      original_user = post.user
      next unless original_user
      next if original_user.staff?

      anon_user = User.find_by(username: SiteSetting.anonymous_students_username)
      next unless anon_user

      # Store the true author information securely
      post.custom_fields['true_author_id'] = original_user.id
      post.custom_fields['true_author_username'] = original_user.username

      # Swap out the post author
      post.user_id = anon_user.id
      post.user = anon_user
    rescue => e
      Rails.logger.error("[PLUGIN anonymous-students] Post swap failed: #{e.message}")
    end
  end

  # 5. WATCHERS: Because the topic now belongs to a bot, the original student won't get notifications. 
  # We must manually force the real student to "watch" the topic after it is created.
  on(:topic_created) do |topic, opts, user|
    begin
      next unless SiteSetting.anonymous_students_enabled
      next unless topic.category_id == SiteSetting.anonymous_students_category_id.to_i
      next if user.staff?

      # 'user' here is the original student who initiated the creation
      TopicUser.change(user.id, topic.id, notification_level: TopicUser.notification_levels[:watching])
    rescue => e
      Rails.logger.error("[PLUGIN anonymous-students] Watcher assignment failed: #{e.message}")
    end
  end
end
