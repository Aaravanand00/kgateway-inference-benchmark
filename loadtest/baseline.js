import http from "k6/http";

export const options = {
  vus: 50,
  duration: "1m",
};

export default function () {
  http.get("http://localhost:8081/infer");
}
