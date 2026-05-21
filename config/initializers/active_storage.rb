# Signed URLs do Active Storage. PHI: prazo curto, mas longo o bastante
# pra que galerias e lightboxes não quebrem em uso normal.
Rails.application.config.active_storage.urls_expire_in = 1.hour
