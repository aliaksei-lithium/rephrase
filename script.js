document.addEventListener('DOMContentLoaded', () => {
    const testBtn = document.getElementById('testBtn');
    const result = document.getElementById('result');

    testBtn.addEventListener('click', async () => {
        result.textContent = 'Loading...';
        
        try {
            const response = await fetch('/api/hello');
            const data = await response.json();
            result.textContent = data.message || 'Success!';
        } catch (error) {
            result.textContent = 'Error: ' + error.message;
        }
    });
});

