<script setup lang="ts">
interface BillingSessionPayload {
  id: string;
  url?: string | null;
}

const notice = ref('');
const noticeError = ref(false);
const busy = ref(false);
const { postJson } = useApi();

const setNotice = (message: string, isError = false) => {
  notice.value = message;
  noticeError.value = isError;
};

const startCheckout = async () => {
  busy.value = true;
  setNotice('Creating checkout session...');
  try {
    const payload = await postJson<BillingSessionPayload>('/billing/checkout-session', {});
    if (!payload.url) {
      throw new Error('checkout_url_missing');
    }
    window.location.href = payload.url;
  } catch (error) {
    setNotice(error instanceof Error ? error.message : 'Checkout failed', true);
  } finally {
    busy.value = false;
  }
};

const openPortal = async () => {
  busy.value = true;
  setNotice('Opening billing portal...');
  try {
    const payload = await postJson<BillingSessionPayload>('/billing/portal-session', {});
    if (!payload.url) {
      throw new Error('portal_url_missing');
    }
    window.location.href = payload.url;
  } catch (error) {
    setNotice(error instanceof Error ? error.message : 'Portal failed', true);
  } finally {
    busy.value = false;
  }
};
</script>

<template>
  <main class="page">
    <section class="card">
      <h1>Billing</h1>
      <p class="muted">Manage your subscription with Stripe.</p>
      <div class="row">
        <button class="primary" :disabled="busy" type="button" @click="startCheckout">Upgrade with Stripe</button>
        <button :disabled="busy" type="button" @click="openPortal">Open billing portal</button>
      </div>
      <div class="row" style="margin-top:0.75rem">
        <NuxtLink to="/account">Back to account</NuxtLink>
      </div>
      <p class="notice" :class="{ error: noticeError }">{{ notice }}</p>
    </section>
  </main>
</template>
