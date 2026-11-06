
(() => {
  "use strict";

  const SUPABASE_URL = "https://afkegyueanjmktgrsnpn.supabase.co";
  const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_AY-KPS5F2lxajImeHv83kw_UmMczbGS";

  const byId = (id) => document.getElementById(id);

  const panel = byId("communityChatPanel");
  const messagesEl = byId("chatMessages");
  const loadingEl = byId("chatLoading");
  const noticeEl = byId("chatNotice");
  const searchInput = byId("chatSearchInput");
  const conversationSummary = byId("chatConversationSummary");
  const profileNameEl = byId("chatProfileName");
  const profileButton = byId("chatProfileButton");
  const emojiPicker = byId("chatEmojiPicker");
  const identityEl = byId("chatIdentity");
  const usernameForm = byId("chatUsernameForm");
  const usernameInput = byId("chatUsername");
  const saveUsernameButton = byId("saveChatUsername");
  const composerEl = byId("chatComposer");
  const currentUsernameEl = byId("chatCurrentUsername");
  const changeUsernameButton = byId("changeChatUsername");
  const messageForm = byId("chatMessageForm");
  const messageInput = byId("chatMessageInput");
  const sendButton = byId("chatSendButton");
  const emojiButton = byId("chatEmoji");
  const conversationsToggle = byId("chatConversationsToggle");
  const conversationList = byId("communityConversationList");

  if (!panel) return;

  let client;
  let currentUser;
  let currentUsername = "";
  let activeMember = false;
  let chatChannel;
  let sending = false;
  let knownMessageIds = new Set();
  let loadedMessages = [];
  let usernamesById = {};

  function setNotice(text = "") {
    noticeEl.textContent = text;
  }

  function showIdentity() {
    identityEl.hidden = false;
    composerEl.hidden = true;
    usernameInput.value = currentUsername;
    usernameInput.focus();
  }

  function showComposer() {
    identityEl.hidden = true;
    composerEl.hidden = false;
    currentUsernameEl.textContent = `Joining as ${currentUsername}`;
    profileNameEl.textContent = currentUsername;
    messageInput.focus();
  }

  function formatTime(value) {
    return new Intl.DateTimeFormat(undefined, {
      hour: "numeric",
      minute: "2-digit"
    }).format(new Date(value));
  }

  function renderMessage(message, username, allowKnown = false) {
    if (!message || (!allowKnown && knownMessageIds.has(String(message.id)))) return;

    knownMessageIds.add(String(message.id));

    const empty = messagesEl.querySelector(".members__chat-empty");
    if (empty) empty.remove();

    const item = document.createElement("article");
    item.className = "members__chat-message";

    if (message.user_id === currentUser.id) {
      item.classList.add("is-mine");
    }

    item.dataset.messageId = String(message.id);

    const meta = document.createElement("div");
    meta.className = "members__chat-message-meta";

    const name = document.createElement("span");
    name.className = "members__chat-message-name";
    name.textContent = username || "Member";

    const time = document.createElement("time");
    time.className = "members__chat-message-time";
    time.dateTime = message.created_at;
    time.textContent = formatTime(message.created_at);

    const body = document.createElement("p");
    body.className = "members__chat-message-body";
    body.textContent = message.message;

    meta.append(name, time);
    item.append(meta, body);
    messagesEl.appendChild(item);

    messagesEl.scrollTop = messagesEl.scrollHeight;
  }

  async function getUsernames(userIds) {
    const uniqueIds = [...new Set(userIds.filter(Boolean))];
    if (!uniqueIds.length) return {};

    const { data, error } = await client
      .from("member_chat_profiles")
      .select("user_id, username")
      .in("user_id", uniqueIds);

    if (error) throw error;

    return Object.fromEntries(
      (data || []).map((profile) => [profile.user_id, profile.username])
    );
  }

  function renderLoadedMessages() {
    messagesEl.replaceChildren();
    const query = searchInput.value.trim().toLowerCase();
    const visibleMessages = loadedMessages.filter((message) =>
      !query || message.message.toLowerCase().includes(query) || (usernamesById[message.user_id] || "").toLowerCase().includes(query)
    );

    if (!visibleMessages.length) {
      const empty = document.createElement("p");
      empty.className = "members__chat-empty";
      empty.textContent = query ? "No messages match that search." : "The table is yours. Start the conversation with a hello.";
      messagesEl.appendChild(empty);
      return;
    }

    visibleMessages.forEach((message) => renderMessage(message, usernamesById[message.user_id], true));
  }

  function renderConversationSummary() {
    conversationSummary.replaceChildren();
    const latest = loadedMessages.at(-1);
    const item = document.createElement("div");
    item.className = "members__conversation is-selected";

    const image = document.createElement("img");
    image.src = "/images/comm.avif";
    image.alt = "";

    const copy = document.createElement("span");
    const title = document.createElement("strong");
    title.textContent = "General Community";
    const preview = document.createElement("small");
    preview.textContent = latest ? `${usernamesById[latest.user_id] || "Member"}: ${latest.message}` : "No messages yet — start the conversation.";
    copy.append(title, preview);

    const count = document.createElement("b");
    count.textContent = String(loadedMessages.length);
    item.append(image, copy, count);
    conversationSummary.append(item);
  }

  async function loadMessages() {
    loadingEl.hidden = false;
    loadingEl.textContent = "Making room at the table…";

    try {
      const { data, error } = await client
        .from("member_chat_messages")
        .select("id, user_id, message, created_at")
        .order("created_at", { ascending: false })
        .limit(60);

      if (error) throw error;

      loadedMessages = (data || []).reverse();
      knownMessageIds = new Set(loadedMessages.map((message) => String(message.id)));
      usernamesById = await getUsernames(loadedMessages.map((message) => message.user_id));
      renderLoadedMessages();
      renderConversationSummary();
      messagesEl.scrollTop = messagesEl.scrollHeight;
    } catch (error) {
      console.error("Loading chat messages failed:", error);
      setNotice("Couldn't load the conversation right now. Please try again.");
      throw error;
    } finally {
      loadingEl.hidden = true;
    }
  }

  async function loadProfile() {
    const { data, error } = await client
      .from("member_chat_profiles")
      .select("username")
      .eq("user_id", currentUser.id)
      .maybeSingle();

    if (error) throw error;

    currentUsername = data?.username || "";

    if (currentUsername) {
      showComposer();
    } else {
      showIdentity();
    }
  }

  async function subscribeToMessages() {
    if (chatChannel) {
      await client.removeChannel(chatChannel);
    }

    chatChannel = client
      .channel("edan-community-messages")
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "member_chat_messages"
        },
        async (payload) => {
          const message = payload.new;

          try {
            const usernames = await getUsernames([message.user_id]);
            usernamesById = { ...usernamesById, ...usernames };
            loadedMessages = [...loadedMessages, message].slice(-60);
            renderMessage(message, usernames[message.user_id]);
            renderConversationSummary();
          } catch (error) {
            console.error("Could not load chat sender:", error);
          }
        }
      )
      .subscribe((status) => {
        if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
          setNotice("Live updates disconnected. Refresh the page to reconnect.");
        } else if (status === "SUBSCRIBED") {
          setNotice("");
        }
      });
  }

  async function openChat() {
    try {
      if (!window.supabase) {
        setNotice("Supabase did not load. Please refresh and try again.");
        return;
      }

      if (
        SUPABASE_URL.startsWith("YOUR_") ||
        SUPABASE_PUBLISHABLE_KEY.startsWith("YOUR_")
      ) {
        setNotice("Add your Supabase project settings to members-chat.js.");
        return;
      }

      client = window.supabase.createClient(
        SUPABASE_URL,
        SUPABASE_PUBLISHABLE_KEY
      );

      const { data: sessionData, error: sessionError } =
        await client.auth.getSession();

      if (sessionError || !sessionData.session) {
        setNotice("Please sign in to enter the members' conversation.");
        return;
      }

      currentUser = sessionData.session.user;

      const { data: membership, error: membershipError } = await client
        .from("memberships")
        .select("membership_tier, membership_status, expires_at")
        .eq("user_id", currentUser.id)
        .maybeSingle();

      if (membershipError) throw membershipError;

      activeMember = Boolean(
        membership &&
        membership.membership_status === "active" &&
        ["monthly", "annual"].includes(membership.membership_tier) &&
        (!membership.expires_at ||
          new Date(membership.expires_at).getTime() > Date.now())
      );

      if (!activeMember) {
        setNotice("Chat access is for active monthly and annual members.");
        return;
      }

      await loadMessages();
      await loadProfile();
      await subscribeToMessages();
    } catch (error) {
      console.error("Community chat error:", error);

      setNotice("The community conversation is unavailable right now. Please try again.");
    } finally {
      loadingEl.hidden = true;
      loadingEl.textContent = "";
    }
  }

  usernameForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!activeMember || !currentUser) return;

    const username = usernameInput.value.trim();

    if (!/^[A-Za-z0-9_]{3,24}$/.test(username)) {
      setNotice("Use 3–24 letters, numbers or underscores.");
      return;
    }

    saveUsernameButton.disabled = true;
    setNotice("Saving your username…");

    try {
      const { error } = await client
        .from("member_chat_profiles")
        .upsert(
          {
            user_id: currentUser.id,
            username,
            updated_at: new Date().toISOString()
          },
          { onConflict: "user_id" }
        );

      if (error) {
        if (error.code === "23505") {
          throw new Error("That username is already taken. Try another.");
        }
        throw error;
      }

      currentUsername = username;
      setNotice("");
      showComposer();
    } catch (error) {
      console.error("Username save error:", error);
      setNotice(error?.code === "23505" ? "That username is already taken. Try another." : "Couldn't save your username. Please try again.");
    } finally {
      saveUsernameButton.disabled = false;
    }
  });

  changeUsernameButton.addEventListener("click", showIdentity);
  profileButton?.addEventListener("click", showIdentity);
  searchInput?.addEventListener("input", () => {
    renderLoadedMessages();
    messagesEl.scrollTop = messagesEl.scrollHeight;
  });

  conversationsToggle?.addEventListener("click", () => {
    const isOpen = conversationList.classList.toggle("is-mobile-open");
    conversationsToggle.setAttribute("aria-expanded", String(isOpen));
  });

  conversationList?.addEventListener("click", () => {
    conversationList.classList.remove("is-mobile-open");
    conversationsToggle?.setAttribute("aria-expanded", "false");
  });

  messageForm.addEventListener("submit", async (event) => {
    event.preventDefault();

    if (!activeMember || !currentUser || !currentUsername || sending) return;

    const message = messageInput.value.trim();
    if (!message) return;

    sending = true;
    sendButton.disabled = true;
    setNotice("");

    try {
      const { data, error } = await client
        .from("member_chat_messages")
        .insert({
          user_id: currentUser.id,
          message
        })
        .select("id, user_id, message, created_at")
        .single();

      if (error || !data) throw error || new Error("Message could not be sent");

      const sentMessage = data;
      loadedMessages = [...loadedMessages, sentMessage].slice(-60);
      knownMessageIds.add(String(sentMessage.id));
      usernamesById[currentUser.id] = currentUsername;
      renderLoadedMessages();
      renderConversationSummary();
      messageInput.value = "";
      messageInput.style.height = "auto";
    } catch (error) {
      console.error("Message send error:", error);
      setNotice("Your message wasn't sent. Please try again.");
    } finally {
      sending = false;
      sendButton.disabled = false;
      messageInput.focus();
    }
  });

  const emojis = ["😊", "😂", "😍", "🙌", "👏", "🤝", "💡", "❤️", "🔥", "✨", "🌿", "🏠", "☀️", "🌱", "🎨", "📚", "🧵", "👋", "🙂", "😮", "🤔", "🙏", "💬", "✅"];

  function insertEmoji(emoji) {
    const start = messageInput.selectionStart;
    const end = messageInput.selectionEnd;
    const value = messageInput.value;
    if (value.length + emoji.length > 1000) return;
    messageInput.value = value.slice(0, start) + emoji + value.slice(end);
    messageInput.focus();
    messageInput.selectionStart = messageInput.selectionEnd = start + emoji.length;
    emojiPicker.hidden = true;
  }

  emojis.forEach((emoji) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "members__chat-emoji-choice";
    button.textContent = emoji;
    button.setAttribute("aria-label", `Insert ${emoji}`);
    button.addEventListener("click", () => insertEmoji(emoji));
    emojiPicker.append(button);
  });

  emojiButton.addEventListener("click", () => {
    if (!activeMember || !currentUsername) {
      showIdentity();
      return;
    }
    emojiPicker.hidden = !emojiPicker.hidden;
  });

  document.addEventListener("click", (event) => {
    if (!emojiPicker.contains(event.target) && event.target !== emojiButton) emojiPicker.hidden = true;
  });

  messageInput.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      messageForm.requestSubmit();
    }
  });

  messageInput.addEventListener("input", () => {
    messageInput.style.height = "auto";
    messageInput.style.height =
      Math.min(messageInput.scrollHeight, 110) + "px";
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") emojiPicker.hidden = true;
  });

  window.addEventListener("beforeunload", () => {
    if (chatChannel && client) {
      client.removeChannel(chatChannel);
    }
  });

  panel.hidden = false;
  openChat();
})();
