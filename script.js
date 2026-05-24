document.addEventListener('DOMContentLoaded', () => {
    const apiKeyInput = document.getElementById('api-key');
    const categoriesContainer = document.getElementById('categories-container');
    const promptTitleEl = document.getElementById('prompt-title');
    const promptWorkspace = document.getElementById('prompt-workspace');
    const emptyState = document.getElementById('empty-state');
    const variablesContainer = document.getElementById('variables-container');
    const finalPromptTextarea = document.getElementById('final-prompt');
    const generateBtn = document.getElementById('generate-btn');
    const llmResponseBox = document.getElementById('llm-response');

    let promptsData = [];
    let currentPrompt = null;
    let variableInputs = {};

    // Load saved API key
    const savedKey = localStorage.getItem('openai_api_key');
    if (savedKey) {
        apiKeyInput.value = savedKey;
    }

    apiKeyInput.addEventListener('change', (e) => {
        localStorage.setItem('openai_api_key', e.target.value);
    });

    // Fetch prompts data
    fetch('prompts.json')
        .then(response => response.json())
        .then(data => {
            promptsData = data;
            renderSidebar(data);
        })
        .catch(err => console.error("Failed to load prompts.json:", err));

    function renderSidebar(data) {
        // Group by category
        const grouped = data.reduce((acc, prompt) => {
            if (!acc[prompt.category]) acc[prompt.category] = [];
            acc[prompt.category].push(prompt);
            return acc;
        }, {});

        categoriesContainer.innerHTML = '';

        for (const [category, prompts] of Object.entries(grouped)) {
            const catDiv = document.createElement('div');
            catDiv.className = 'category';

            const catTitle = document.createElement('div');
            catTitle.className = 'category-title';
            catTitle.textContent = category;

            const ul = document.createElement('ul');
            ul.className = 'prompt-list';

            prompts.forEach(prompt => {
                const li = document.createElement('li');
                li.className = 'prompt-item';
                li.textContent = prompt.title;
                li.onclick = () => selectPrompt(prompt, li);
                ul.appendChild(li);
            });

            catTitle.onclick = () => {
                catDiv.classList.toggle('active');
            };

            catDiv.appendChild(catTitle);
            catDiv.appendChild(ul);
            categoriesContainer.appendChild(catDiv);
        }
    }

    function selectPrompt(prompt, listItemElement) {
        // UI updates
        document.querySelectorAll('.prompt-item').forEach(el => el.classList.remove('active'));
        if (listItemElement) listItemElement.classList.add('active');

        emptyState.style.display = 'none';
        promptWorkspace.style.display = 'grid';
        promptTitleEl.textContent = prompt.title;

        currentPrompt = prompt;
        variableInputs = {};

        renderVariables(prompt);
        updateFinalPrompt();

        // Reset response
        llmResponseBox.innerHTML = '<p class="placeholder-text">Response will appear here...</p>';
    }

    function renderVariables(prompt) {
        variablesContainer.innerHTML = '';

        if (!prompt.variables || prompt.variables.length === 0) {
            variablesContainer.innerHTML = '<p>No variables to fill for this prompt.</p>';
            return;
        }

        prompt.variables.forEach(variable => {
            const group = document.createElement('div');
            group.className = 'variable-group';

            const label = document.createElement('label');
            label.textContent = variable;

            // Use textarea for longer text expectations like pasting content
            const isLongText = variable.toLowerCase().includes('paste') || variable.toLowerCase().includes('content');
            const input = document.createElement(isLongText ? 'textarea' : 'input');

            if (isLongText) {
                input.rows = 4;
            } else {
                input.type = 'text';
            }

            input.placeholder = `Enter ${variable}...`;
            input.oninput = updateFinalPrompt;

            variableInputs[variable] = input;

            group.appendChild(label);
            group.appendChild(input);
            variablesContainer.appendChild(group);
        });
    }

    function updateFinalPrompt() {
        if (!currentPrompt) return;

        let finalPrompt = currentPrompt.text;

        for (const [varName, inputEl] of Object.entries(variableInputs)) {
            const val = inputEl.value.trim() || `[${varName}]`;
            // Replace all occurrences of the exact variable placeholder
            finalPrompt = finalPrompt.split(`[${varName}]`).join(val);
        }

        finalPromptTextarea.value = finalPrompt;
    }

    generateBtn.addEventListener('click', async () => {
        const apiKey = apiKeyInput.value.trim();
        if (!apiKey) {
            alert('Please enter your OpenAI API key in the sidebar.');
            return;
        }

        const promptText = finalPromptTextarea.value;
        if (!promptText) return;

        generateBtn.disabled = true;
        generateBtn.textContent = 'Generating...';
        llmResponseBox.innerHTML = '<p class="loading">Waiting for LLM response...</p>';

        try {
            const response = await fetch('https://api.openai.com/v1/chat/completions', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${apiKey}`
                },
                body: JSON.stringify({
                    model: 'gpt-4o-mini', // Using a fast/cheap model by default
                    messages: [
                        { role: 'user', content: promptText }
                    ],
                    temperature: 0.7
                })
            });

            if (!response.ok) {
                const errData = await response.json();
                throw new Error(errData.error?.message || 'API request failed');
            }

            const data = await response.json();
            const resultText = data.choices[0].message.content;

            // Basic markdown-like formatting for output (newlines to <br>)
            // Ideally use a markdown parser, but this works for plain text
            llmResponseBox.textContent = resultText;

        } catch (error) {
            console.error(error);
            llmResponseBox.innerHTML = `<p class="error-text">Error: ${error.message}</p>`;
        } finally {
            generateBtn.disabled = false;
            generateBtn.textContent = 'Generate Request';
        }
    });
});