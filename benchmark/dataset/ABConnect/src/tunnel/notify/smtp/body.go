package smtp

const Body = `<!DOCTYPE html>
<html>
<head>
    <style>
        body { font-family: sans-serif; line-height: 1.6; margin: 20px; }
        .card { border: 1px solid #ddd; border-radius: 5px; padding: 15px; margin-bottom: 20px; background-color: #f9f9f9; }
        .card-title { font-size: 16px; font-weight: bold; color: #333; margin-bottom: 10px; }
        .card-details p { margin: 5px 0; display: flex; }
        .label { width: 200px; text-align: left; color: #555; }
        .value { text-align: left; flex: 1; color: #333; }
        .asset-label { font-size: 14px; font-weight: bold; color: #444; margin-top: 10px; margin-bottom: 5px; }
        .card-divider { border-top: 1px dashed #ccc; margin: 10px 0; }
    </style>
</head>
<body>

<p>Dear Chrononauts,</p>

<p>Please find below the daily bridge statement for %s:</p>

%s

<p>Thank you for your attention.</p>

<p>Sincerely,</p>

<p>%s</p>

</body>
</html>
`

const CardStart = `<div class="card">
    <div class="card-title">%s-%s</div>
    <div class="card-details">
        <p><span class="label">Total Deposit:</span> <span class="value">%s %s</span></p>
		<p><span class="label">Total Withdraw:</span> <span class="value">%s %s</span></p>
 		<p><span class="label">Total Fee:</span> <span class="value">%s %s</span></p>
		<p><span class="label">Total Deposit (Last Day):</span> <span class="value">%s %s</span></p>
		<p><span class="label">Total Withdraw (Last Day):</span> <span class="value">%s %s</span></p>`
const CardItem = `<p><span class="label">%s:</span><span class="value">%s %s</span></p>`
const CardEnd = `
    </div>
</div>`

const CardPair0 = `<div class="card">
    <div class="card-title">%s-%s</div>
    <div class="card-details">
        <p><span class="label">Total Deposit:</span> <span class="value">%s %s</span></p>
		<p><span class="label">Total Withdraw:</span> <span class="value">%s %s</span></p>
        <p><span class="label">Total Fee:</span> <span class="value">%s %s</span></p>
		<p><span class="label">Total Deposit (Last Day):</span> <span class="value">%s %s</span></p>
		<p><span class="label">Total Withdraw (Last Day):</span> <span class="value">%s %s</span></p>
    </div>
</div>`

const CardPair = `<div class="card">
    <div class="card-title">%s@%s <=> %s@%s</div>
    <div class="card-details">
        <p class="asset-label">Asset A (%s-%s)</p>
        <p><span class="label">Total Deposit:</span> <span class="value">%s %s</span></p>
        <p><span class="label">Total Withdraw:</span> <span class="value">%s %s</span></p>
        <p><span class="label">Total Fee:</span> <span class="value">%s %s</span></p>
        <p><span class="label">Total Deposit (Last Day):</span> <span class="value">%s %s</span></p>
        <p><span class="label">Total Withdraw (Last Day):</span> <span class="value">%s %s</span></p>

        <div class="card-divider"></div>

        <p class="asset-label">Asset B (%s-%s):</p>
        <p><span class="label">Total Deposit:</span> <span class="value">%s %s</span></p>
        <p><span class="label">Total Withdraw:</span> <span class="value">%s %s</span></p>
		<p><span class="label">Total Fee:</span> <span class="value">%s %s</span></p>
        <p><span class="label">Total Deposit (Last Day):</span> <span class="value">%s %s</span></p>
        <p><span class="label">Total Withdraw (Last Day):</span> <span class="value">%s %s</span></p>
    </div>
</div>`
