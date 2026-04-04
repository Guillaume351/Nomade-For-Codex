<script setup lang="ts">
const { fetchSession, isAuthenticated } = useAuthSession();
await fetchSession();
await navigateTo(isAuthenticated.value ? "/account" : "/login");
</script>
