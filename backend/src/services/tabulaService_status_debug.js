// Add this debug logging around line 135 to see status fields
console.log(`Job ${job.id} status info:`, {
  job_status: job.status,
  details_status: details?.Status,
  details_status_lowercase: details?.status,
  all_detail_keys: details ? Object.keys(details).filter(k => k.toLowerCase().includes('status')) : []
});
