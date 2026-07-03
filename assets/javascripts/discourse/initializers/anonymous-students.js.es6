import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "anonymous-students",

  initialize() {
    withPluginApi("0.8.37", (api) => {
      // Use the safer page/post decorator architecture
      api.includePostAttributes("true_author_username");

      api.decorateWidget("post-contents:after", (helper) => {
        const post = helper.getModel();
        const currentUser = api.getCurrentUser();
        
        // Safe checks: Only execute if post exists, user is staff, and data is present
        if (post && currentUser && currentUser.staff && post.true_author_username) {
          return helper.h(
            "div.anonymous-students-true-author",
            `Admin audit: submitted by ${post.true_author_username}`
          );
        }
      });
    });
  },
};