import { memo } from "react";
import { Provider } from "react-redux";
import { Navigate, Route, Routes } from "react-router";
import HomePage from "./pages/home/HomePage";
import TestPage from "./pages/test/TestPage";
import store from "./store";
import { initSearchData } from "./utils/searchData";

// initSearchData();
const App = memo(function App() {
  return (
    // <HomePage />
    <Provider store={store}>
      <Routes>
        <Route path="/" element={<Navigate to="/home" />} />
        <Route path="/home" element={<HomePage />} />
        <Route path="/home/test/:id/:page" element={<TestPage />} />
      </Routes>
    </Provider>
  );
});
export default App;