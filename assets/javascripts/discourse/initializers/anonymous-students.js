import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "anonymous-students",

  initialize() {
    // 0.8.37 is old; we bump the API version requirement to access the new methods
    withPluginApi("1.34.0", (api) => {
      
      // Update 1: The modern replacement for includePostAttributes
      api.addTrackedPostProperties(["true_author_username"]);

      // Update 2: The modern replacement for decorateWidget
      api.decorateCookedElement((element, helper) => {
        // Safety guard: ensure we are looking at a post
        if (!helper || !helper.getModel) return;
        
        const post = helper.getModel();
        const currentUser = api.getCurrentUser();

        // Check if data exists and user is a staff member
        if (post && currentUser && currentUser.staff && post.true_author_username) {
          
          // Create the HTML div safely
          const auditDiv = document.createElement("div");
          auditDiv.className = "anonymous-students-true-author";
          auditDiv.textContent = `Admin audit: submitted by ${post.true_author_username}`;
          
          // Append it to the bottom of the post text
          element.appendChild(auditDiv);
        }
      }, { id: "anonymous-students-audit" });
      
    });
  },
};