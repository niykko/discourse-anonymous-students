import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "anonymous-students",

  initialize() {
    withPluginApi("1.34.0", (api) => {
      
      // FIX: Pass strings as arguments, do NOT wrap them in an array.
      api.addTrackedPostProperties(
        "true_author_id",
        "true_author_username",
        "anonymous_students_original_poster"
      );

      api.decorateCookedElement((element, helper) => {
        // Safety guard: ensure we are looking at a post
        if (!helper || !helper.getModel) return;
        
        const post = helper.getModel();
        const currentUser = api.getCurrentUser();

        if (post?.anonymous_students_original_poster) {
          const originalPosterBadge = document.createElement("div");
          originalPosterBadge.className = "anonymous-students-original-poster";
          originalPosterBadge.textContent = "Original poster";
          element.appendChild(originalPosterBadge);
        }

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
