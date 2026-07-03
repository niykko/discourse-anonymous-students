import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "anonymous-students",

  initialize() {
    withPluginApi("0.8.37", (api) => {
      api.decorateWidget("post-contents:after", (helper) => {
        const post = helper.getModel();
        if (!post) {
          return;
        }

        const actualUsername = post.true_author_username;
        if (!actualUsername) {
          return;
        }

        const currentUser = api.getCurrentUser();
        if (!currentUser || !currentUser.staff) {
          return;
        }

        return helper.h(
          "div.anonymous-students-true-author",
          `Admin audit: submitted by ${actualUsername}`
        );
      });
    });
  },
};
