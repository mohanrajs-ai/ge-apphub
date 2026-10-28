/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        gemini: {
          blue: '#1a73e8',
          indigo: '#4f46e5',
          purple: '#9333ea',
        },
      },
    },
  },
  plugins: [],
};
